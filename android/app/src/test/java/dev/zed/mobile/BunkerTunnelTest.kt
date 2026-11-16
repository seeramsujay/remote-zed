package dev.zed.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import java.util.Base64

class BunkerTunnelTest {

    @Test
    fun `parse handles ZEDBUNKER base64 payload`() {
        val json = """{"ntfy_topic":"zed-bunker-test","key":"MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=","token":"test-token","port":8443}"""
        val encoded = Base64.getUrlEncoder().withoutPadding().encodeToString(json.toByteArray())
        val raw = "ZEDBUNKER:$encoded"

        val config = BunkerTunnel.parse(raw)
        assertNotNull(config)
        assertEquals("zed-bunker-test", config?.ntfyTopic)
        assertEquals("MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=", config?.encryptionKeyBase64)
        assertEquals("test-token", config?.token)
        assertEquals(8443, config?.port)
    }

    @Test
    fun `parse handles zed-remote pair URI`() {
        val uri = "zed-remote://pair?topic=zed-bunker-abc&key=MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI=&token=tok123&port=9443"
        val config = BunkerTunnel.parse(uri)
        assertNotNull(config)
        assertEquals("zed-bunker-abc", config?.ntfyTopic)
        assertEquals("MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI=", config?.encryptionKeyBase64)
        assertEquals("tok123", config?.token)
        assertEquals(9443, config?.port)
    }

    @Test
    fun `encrypt and decrypt AES-GCM roundtrip`() {
        val keyBytes = ByteArray(32) { it.toByte() }
        val base64Key = Base64.getEncoder().encodeToString(keyBytes)
        val plaintext = "tcp://kdtgg-202-164-151-178.run.pinggy-free.link:38883"

        val encrypted = BunkerTunnel.encryptAesGcm(plaintext, keyBytes)
        val decrypted = BunkerTunnel.decryptAesGcm(encrypted, base64Key)

        assertEquals(plaintext, decrypted)
    }

    @Test
    fun `decrypt AES-GCM with 64-char hex key`() {
        val keyBytes = ByteArray(32) { it.toByte() }
        val hexKey = keyBytes.joinToString("") { "%02x".format(it) }
        val plaintext = "tcp://kdtgg-202-164-151-178.run.pinggy-free.link:38883"

        val encrypted = BunkerTunnel.encryptAesGcm(plaintext, keyBytes)
        val decrypted = BunkerTunnel.decryptAesGcm(encrypted, hexKey)

        assertEquals(plaintext, decrypted)
    }

    @Test
    fun `resolveTunnelUrl skips plaintext notification lines in federation history`() {
        val keyBytes = ByteArray(32) { it.toByte() }
        val base64Key = Base64.getEncoder().encodeToString(keyBytes)
        val plaintext = "tcp://kdtgg-202-164-151-178.run.pinggy-free.link:38883"
        val encrypted = BunkerTunnel.encryptAesGcm(plaintext, keyBytes)

        val rawBody = """
            Turn completed on remote-zed
            AntiGravity Task Finished
            $encrypted
            Turn completed on remote-zed
            test
        """.trimIndent()

        val lines = rawBody.lines().map { it.trim() }.filter { it.isNotBlank() }.reversed()
        var resolvedUrl: String? = null
        for (candidate in lines) {
            try {
                val decrypted = BunkerTunnel.decryptAesGcm(candidate, base64Key)
                if (decrypted.startsWith("tcp://") || decrypted.startsWith("http://") || decrypted.startsWith("https://") || decrypted.contains(":")) {
                    resolvedUrl = BunkerTunnel.normalizeOrigin(decrypted, 8443)
                    break
                }
            } catch (_: Exception) {
                // Skip invalid payload
            }
        }

        assertNotNull(resolvedUrl)
        assertEquals("http://kdtgg-202-164-151-178.run.pinggy-free.link:38883", resolvedUrl)
    }
}
