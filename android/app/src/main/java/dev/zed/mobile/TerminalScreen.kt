package dev.zed.mobile

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch

data class TerminalEntry(
    val text: String,
    val isInput: Boolean = false,
    val isError: Boolean = false,
    val cwd: String? = null,
)

/**
 * Material 3 / Termux-style Interactive Mobile Terminal.
 *
 * Allows starting off-the-grid projects, running `mkdir`, `cargo new`, compiling binaries,
 * or executing git commands through the secure encrypted tunnel directly from mobile.
 */
@Composable
fun TerminalScreen(
    currentCwd: String = "~/Projects",
    onExecuteCommand: suspend (String) -> TerminalExecResponse,
    modifier: Modifier = Modifier,
) {
    val entries = remember {
        mutableStateListOf(
            TerminalEntry(text = "Zed Remote Interactive Terminal (Bunker Active)"),
            TerminalEntry(text = "Zero-Trust Tunnel • AES-256-GCM Encrypted\n"),
        )
    }

    var inputCommand by remember { mutableStateOf("") }
    var running by remember { mutableStateOf(false) }
    var cwd by remember { mutableStateOf(currentCwd) }

    val history = remember { mutableStateListOf<String>() }
    var historyIndex by remember { mutableIntStateOf(-1) }

    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    fun runCmd(cmdText: String) {
        val trimmed = cmdText.trim()
        if (trimmed.isEmpty() || running) return

        history.add(trimmed)
        historyIndex = history.size

        entries.add(TerminalEntry(text = trimmed, isInput = true, cwd = cwd))
        inputCommand = ""
        running = true

        scope.launch {
            try {
                val res = onExecuteCommand(trimmed)
                cwd = res.cwd
                if (res.stdout.isNotEmpty()) {
                    entries.add(TerminalEntry(text = res.stdout))
                }
                if (res.stderr.isNotEmpty()) {
                    entries.add(TerminalEntry(text = res.stderr, isError = true))
                }
            } catch (e: Exception) {
                entries.add(TerminalEntry(text = "Error: ${e.message}", isError = true))
            } finally {
                running = false
                listState.animateScrollToItem((entries.size - 1).coerceAtLeast(0))
            }
        }
    }

    Surface(
        modifier = modifier
            .fillMaxSize()
            .imePadding(),
        color = MaterialTheme.colorScheme.surfaceContainerLowest,
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Header: CWD & Actions
            Surface(
                color = MaterialTheme.colorScheme.surfaceContainer,
                tonalElevation = 2.dp,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Default.Terminal,
                        contentDescription = "Terminal",
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = cwd,
                        style = TextStyle(
                            fontFamily = MonoFamily,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurface,
                        ),
                        maxLines = 1,
                        modifier = Modifier.weight(1f),
                    )
                    if (running) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(14.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    IconButton(
                        onClick = {
                            entries.clear()
                            entries.add(TerminalEntry(text = "Terminal cleared.\n"))
                        },
                        modifier = Modifier.size(28.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.DeleteSweep,
                            contentDescription = "Clear",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }

            // Output Console
            SelectionContainer(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            ) {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(entries) { entry ->
                        if (entry.isInput) {
                            Row(
                                modifier = Modifier.padding(top = 8.dp, bottom = 2.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    text = "$ ",
                                    style = TextStyle(
                                        fontFamily = MonoFamily,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color(0xFF34D399), // Emerald
                                    ),
                                )
                                Text(
                                    text = entry.text,
                                    style = TextStyle(
                                        fontFamily = MonoFamily,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.onSurface,
                                    ),
                                )
                            }
                        } else {
                            Text(
                                text = entry.text,
                                style = TextStyle(
                                    fontFamily = MonoFamily,
                                    fontSize = 12.5.sp,
                                    lineHeight = 18.sp,
                                    color = if (entry.isError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                                ),
                            )
                        }
                    }
                }
            }

            // Mobile Quick-Keys Bar (Termux Style)
            Surface(
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TermuxQuickKey("TAB") { inputCommand += "\t" }
                    TermuxQuickKey("~") { inputCommand += "~" }
                    TermuxQuickKey("/") { inputCommand += "/" }
                    TermuxQuickKey("-") { inputCommand += "-" }
                    TermuxQuickKey("|") { inputCommand += "|" }
                    TermuxQuickKey("..") { inputCommand += ".." }
                    TermuxQuickKey("↑") {
                        if (history.isNotEmpty() && historyIndex > 0) {
                            historyIndex--
                            inputCommand = history[historyIndex]
                        }
                    }
                    TermuxQuickKey("↓") {
                        if (history.isNotEmpty() && historyIndex < history.size - 1) {
                            historyIndex++
                            inputCommand = history[historyIndex]
                        } else {
                            historyIndex = history.size
                            inputCommand = ""
                        }
                    }
                    TermuxQuickKey("Ctrl+C") { runCmd("^C") }
                    TermuxQuickKey("CLEAR") {
                        entries.clear()
                    }
                }
            }

            // Command Input Row
            Surface(
                color = MaterialTheme.colorScheme.surfaceContainer,
                tonalElevation = 3.dp,
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding(),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "$ ",
                        style = TextStyle(
                            fontFamily = MonoFamily,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFF34D399),
                        ),
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    BasicTextField(
                        value = inputCommand,
                        onValueChange = { inputCommand = it },
                        modifier = Modifier.weight(1f),
                        textStyle = TextStyle(
                            fontFamily = MonoFamily,
                            fontSize = 13.5.sp,
                            color = MaterialTheme.colorScheme.onSurface,
                        ),
                        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                        keyboardActions = KeyboardActions(onGo = { runCmd(inputCommand) }),
                        decorationBox = { innerTextField ->
                            if (inputCommand.isEmpty()) {
                                Text(
                                    text = "type command (mkdir, cargo, ls)...",
                                    style = TextStyle(
                                        fontFamily = MonoFamily,
                                        fontSize = 12.5.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                                    ),
                                )
                            }
                            innerTextField()
                        },
                    )
                    IconButton(
                        onClick = { runCmd(inputCommand) },
                        enabled = inputCommand.isNotBlank() && !running,
                        modifier = Modifier.size(32.dp),
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                            contentDescription = "Run",
                            tint = if (inputCommand.isNotBlank() && !running) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant.copy(
                                alpha = 0.4f
                            ),
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TermuxQuickKey(
    label: String,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(6.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHighest,
        tonalElevation = 1.dp,
    ) {
        Text(
            text = label,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
            style = TextStyle(
                fontFamily = MonoFamily,
                fontSize = 11.5.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
            ),
        )
    }
}

data class TerminalExecResponse(
    val stdout: String = "",
    val stderr: String = "",
    val exitCode: Int = 0,
    val cwd: String = "",
)
