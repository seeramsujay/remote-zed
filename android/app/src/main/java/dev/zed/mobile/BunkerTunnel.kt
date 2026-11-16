package dev.zed.mobile

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.nio.charset.StandardCharsets
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Bunker Tunnel Zero-Knowledge Rendezvous client.
 *
 * Fortinet and campus firewalls block WireGuard / Tailscale (UDP 41641).
 * The Bunker Tunnel forwards traffic through an SSH reverse tunnel over port 443
 * (indistinguishable from TLS/HTTPS) to a dynamic endpoint, published to an ephemeral,
 * 48+ character cryptographically random ntfy.sh channel and encrypted with AES-256-GCM.
 */
data class BunkerConfig(
    val ntfyTopic: String,
    val encryptionKeyBase64: String,
    val token: String,
    val port: Int = 8443,
)

object BunkerTunnel {
    const val PREFIX = "ZEDBUNKER:"
    private const val GCM_TAG_LENGTH_BITS = 128
    private const val GCM_IV_LENGTH_BYTES = 12

    /**
     * Checks if a scanned QR code represents a Bunker Tunnel ticket and parses it.
     */
    fun parse(raw: String): BunkerConfig? {
        val jsonStr = when {
            raw.startsWith(PREFIX) -> {
                val encoded = raw.removePrefix(PREFIX).trim()
                try {
                    String(Base64.getUrlDecoder().decode(encoded), StandardCharsets.UTF_8)
                } catch (_: Exception) {
                    try {
                        String(Base64.getDecoder().decode(encoded), StandardCharsets.UTF_8)
                    } catch (_: Exception) {
                        return null
                    }
                }
            }

            raw.trim().startsWith("{") && raw.contains("ntfy_topic") -> raw.trim()
            raw.trim().startsWith("zed-remote://pair") -> {
                try {
                    val uri = java.net.URI(raw.trim())
                    val query = uri.rawQuery ?: ""
                    val params = query.split('&').associate {
                        val parts = it.split('=', limit = 2)
                        parts[0] to (if (parts.size > 1) java.net.URLDecoder.decode(parts[1], "UTF-8") else "")
                    }
                    val topic = params["topic"] ?: return null
                    val key = params["key"] ?: return null
                    val token = params["token"] ?: ""
                    val port = params["port"]?.toIntOrNull() ?: 8443
                    return BunkerConfig(ntfyTopic = topic, encryptionKeyBase64 = key, token = token, port = port)
                } catch (_: Exception) {
                    return null
                }
            }
            else -> return null
        }

        return try {
            val json = JsonParser.parseString(jsonStr).asJsonObject
            val topic = json.get("ntfy_topic")?.asString ?: return null
            val key = json.get("key")?.asString ?: json.get("encryption_key")?.asString ?: return null
            val token = json.get("token")?.asString ?: ""
            val port = json.get("port")?.asInt ?: 8443
            BunkerConfig(ntfyTopic = topic, encryptionKeyBase64 = key, token = token, port = port)
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Resolves the live, decrypted tunnel origin from the encrypted rendezvous federation.
     * Tries high-availability community relays and official ntfy.sh with automatic failover.
     */
    suspend fun resolveTunnelUrl(config: BunkerConfig, client: OkHttpClient = OkHttpClient()): String =
        withContext(Dispatchers.IO) {
            val servers = listOf(
                "https://ntfy.sh",
                "https://ntfy.adminforge.de",
            )
            var lastError: Exception? = null
            for (server in servers) {
                try {
                    val ntfyUrl = "$server/${config.ntfyTopic}/raw?poll=1&since=all"
                    val request = Request.Builder()
                        .url(ntfyUrl)
                        .header("User-Agent", "ZedRemote-Android/2.0")
                        .build()

                    val response = client.newCall(request).execute()
                    if (!response.isSuccessful) {
                        continue
                    }

                    val body = response.body?.string()?.trim() ?: continue
                    val lines = body.lines().map { it.trim() }.filter { it.isNotBlank() }.reversed()
                    for (candidate in lines) {
                        try {
                            val decrypted = decryptAesGcm(candidate, config.encryptionKeyBase64)
                            if (decrypted.startsWith("tcp://") || decrypted.startsWith("http://") || decrypted.startsWith("https://") || decrypted.contains(":")) {
                                return@withContext normalizeOrigin(decrypted, config.port)
                            }
                        } catch (_: Exception) {
                            // Non-ciphertext payload (e.g., plaintext notification line); continue scanning older lines
                        }
                    }
                } catch (e: Exception) {
                    lastError = e
                }
            }

            throw GatewayException(
                lastError?.message
                    ?: "Failed to resolve rendezvous endpoint from federation. Ensure zed-tunnel is running on your desktop."
            )
        }

    /**
     * Decrypts an AES-256-GCM ciphertext payload formatted as:
     * Base64( 12-byte IV + Ciphertext + 16-byte Tag ) or Hex( IV + Ciphertext + Tag ).
     */
    fun decryptAesGcm(encryptedPayload: String, base64Key: String): String {
        val keyBytes = if (base64Key.matches(Regex("^[0-9a-fA-F]{64}$"))) {
            base64Key.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        } else {
            try {
                Base64.getDecoder().decode(base64Key)
            } catch (_: Exception) {
                Base64.getUrlDecoder().decode(base64Key)
            }
        }
        require(keyBytes.size == 32) { "AES-256 key must be exactly 32 bytes (got ${keyBytes.size})." }

        val payloadBytes = try {
            if (encryptedPayload.matches(Regex("^[0-9a-fA-F]+$"))) {
                // Hex-encoded
                encryptedPayload.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
            } else {
                // Base64-encoded
                try {
                    Base64.getDecoder().decode(encryptedPayload)
                } catch (_: Exception) {
                    Base64.getUrlDecoder().decode(encryptedPayload)
                }
            }
        } catch (e: Exception) {
            throw IllegalArgumentException("Malformed bunker encrypted payload: ${e.message}")
        }

        require(payloadBytes.size > GCM_IV_LENGTH_BYTES + 16) {
            "Ciphertext payload too short to contain IV and authentication tag."
        }

        val iv = payloadBytes.copyOfRange(0, GCM_IV_LENGTH_BYTES)
        val ciphertextWithTag = payloadBytes.copyOfRange(GCM_IV_LENGTH_BYTES, payloadBytes.size)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val keySpec = SecretKeySpec(keyBytes, "AES")
        val gcmSpec = GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv)

        cipher.init(Cipher.DECRYPT_MODE, keySpec, gcmSpec)
        val decryptedBytes = cipher.doFinal(ciphertextWithTag)
        return String(decryptedBytes, StandardCharsets.UTF_8).trim()
    }

    /**
     * Encrypts plaintext with AES-256-GCM: IV (12 bytes) + Ciphertext + Tag (16 bytes), returned as Base64.
     */
    fun encryptAesGcm(plaintext: String, keyBytes: ByteArray): String {
        require(keyBytes.size == 32) { "AES-256 key must be exactly 32 bytes." }
        val iv = ByteArray(GCM_IV_LENGTH_BYTES).apply {
            java.security.SecureRandom().nextBytes(this)
        }

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val keySpec = SecretKeySpec(keyBytes, "AES")
        val gcmSpec = GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv)

        cipher.init(Cipher.ENCRYPT_MODE, keySpec, gcmSpec)
        val ciphertext = cipher.doFinal(plaintext.toByteArray(StandardCharsets.UTF_8))

        val combined = ByteArray(iv.size + ciphertext.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(ciphertext, 0, combined, iv.size, ciphertext.size)

        return Base64.getEncoder().encodeToString(combined)
    }

    /**
     * Normalizes a raw tunnel string (e.g. "tcp://t.pinggy.io:44551" or "http://...") into an HTTP origin.
     */
    fun normalizeOrigin(raw: String, fallbackPort: Int): String {
        val cleaned = raw.removePrefix("tcp://").removePrefix("ssl://").trim()
        return if (cleaned.startsWith("http://") || cleaned.startsWith("https://")) {
            cleaned
        } else {
            // "hostname:port"
            "http://$cleaned"
        }
    }
}
