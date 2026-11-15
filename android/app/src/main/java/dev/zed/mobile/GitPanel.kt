package dev.zed.mobile

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AccountTree
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Commit
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Material 3 Git Control Panel Drawer.
 *
 * Modeled after Zed Desktop's right-hand Git panel, providing:
 * - Branch inspection & switching
 * - Staged vs Unstaged file management with selective staging
 * - Commit compose with "Commit" and "Stage All & Commit"
 * - Push to remote repository
 * - Interactive Git commit graph & history log
 */
@Composable
fun GitPanelDrawer(
    state: MobileState,
    vm: ZedViewModel,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var selectedTab by remember { mutableIntStateOf(0) }
    var commitMessage by remember { mutableStateOf("") }
    var showBranchesDialog by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        vm.loadGitStatus()
        vm.loadGitLog()
    }

    val status = state.gitStatus
    val branch = status?.branch ?: "HEAD"
    val stagedFiles = status?.files?.filter { it.staged } ?: emptyList()
    val unstagedFiles = status?.files?.filter { !it.staged } ?: emptyList()

    if (showBranchesDialog) {
        AlertDialog(
            onDismissRequest = { showBranchesDialog = false },
            title = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.AccountTree, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Git Branches", style = MaterialTheme.typography.titleMedium)
                }
            },
            text = {
                LazyColumn(modifier = Modifier.fillMaxWidth()) {
                    items(state.gitBranches) { b ->
                        val isCurrent = b == branch || b.endsWith("/$branch")
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(8.dp))
                                .background(if (isCurrent) ZedColors.Subtle else Color.Transparent)
                                .clickable {
                                    showBranchesDialog = false
                                }
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = b,
                                style = TextStyle(
                                    fontFamily = MonoFamily,
                                    fontSize = 13.sp,
                                    fontWeight = if (isCurrent) FontWeight.Bold else FontWeight.Normal,
                                    color = if (isCurrent) MaterialTheme.colorScheme.primary else ZedColors.DarkText,
                                ),
                                modifier = Modifier.weight(1f),
                            )
                            if (isCurrent) {
                                Icon(
                                    imageVector = Icons.Default.Check,
                                    contentDescription = "Current",
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(16.dp),
                                )
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showBranchesDialog = false }) {
                    Text("Close")
                }
            },
        )
    }

    ModalDrawerSheet(
        modifier = modifier
            .width(320.dp)
            .fillMaxHeight(),
        drawerContainerColor = ZedColors.DarkSurface,
        drawerContentColor = ZedColors.DarkText,
        drawerShape = RoundedCornerShape(topStart = 24.dp, bottomStart = 24.dp),
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Header Bar: Branch selector, Refresh, Push, Close
            Surface(
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Branch Selector Chip
                    Row(
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(MaterialTheme.colorScheme.surfaceContainer)
                            .clickable { showBranchesDialog = true }
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = Icons.Default.AccountTree,
                            contentDescription = "Branch",
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(15.dp),
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = branch,
                            style = TextStyle(
                                fontFamily = MonoFamily,
                                fontSize = 12.5.sp,
                                fontWeight = FontWeight.Bold,
                                color = ZedColors.DarkText,
                            ),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.widthIn(max = 130.dp),
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Icon(
                            imageVector = Icons.Default.KeyboardArrowDown,
                            contentDescription = null,
                            tint = ZedColors.DarkMuted,
                            modifier = Modifier.size(16.dp),
                        )
                    }

                    Spacer(modifier = Modifier.weight(1f))

                    // Push button
                    IconButton(
                        onClick = { vm.pushGit() },
                        modifier = Modifier.size(32.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.ArrowUpward,
                            contentDescription = "Push to Remote",
                            tint = Color(0xFF34D399),
                            modifier = Modifier.size(18.dp),
                        )
                    }

                    // Refresh button
                    IconButton(
                        onClick = {
                            vm.loadGitStatus()
                            vm.loadGitLog()
                        },
                        modifier = Modifier.size(32.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Refresh,
                            contentDescription = "Refresh",
                            tint = ZedColors.DarkMuted,
                            modifier = Modifier.size(18.dp),
                        )
                    }

                    // Close button
                    IconButton(
                        onClick = onClose,
                        modifier = Modifier.size(32.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = "Close Git Panel",
                            tint = ZedColors.DarkMuted,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }

            // Tab Switcher: Changes vs Graph & Log
            TabRow(
                selectedTabIndex = selectedTab,
                containerColor = MaterialTheme.colorScheme.surfaceContainer,
                contentColor = ZedColors.DarkText,
                indicator = { tabPositions ->
                    TabRowDefaults.SecondaryIndicator(
                        Modifier.tabIndicatorOffset(tabPositions[selectedTab]),
                        color = MaterialTheme.colorScheme.primary,
                    )
                },
            ) {
                Tab(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    text = {
                        val totalChanges = stagedFiles.size + unstagedFiles.size
                        Text(
                            text = if (totalChanges > 0) "Changes ($totalChanges)" else "Changes",
                            style = MaterialTheme.typography.labelMedium,
                        )
                    },
                )
                Tab(
                    selected = selectedTab == 1,
                    onClick = {
                        selectedTab = 1
                        vm.loadGitLog()
                    },
                    text = {
                        Text("Graph & Log", style = MaterialTheme.typography.labelMedium)
                    },
                )
            }

            if (state.gitLoading && status == null) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
            } else {
                when (selectedTab) {
                    0 -> GitChangesTab(
                        stagedFiles = stagedFiles,
                        unstagedFiles = unstagedFiles,
                        commitMessage = commitMessage,
                        onCommitMessageChange = { commitMessage = it },
                        onStageFile = { file -> vm.stageGit(listOf(file.path)) },
                        onUnstageFile = { file -> vm.unstageGit(listOf(file.path)) },
                        onStageAll = { vm.stageGit(unstagedFiles.map { it.path }) },
                        onUnstageAll = { vm.unstageGit(stagedFiles.map { it.path }) },
                        onCommit = {
                            vm.commitGit(commitMessage, stageAll = false)
                            commitMessage = ""
                        },
                        onStageAllAndCommit = {
                            vm.commitGit(commitMessage, stageAll = true)
                            commitMessage = ""
                        },
                    )

                    1 -> GitGraphTab(commits = state.gitCommits)
                }
            }
        }
    }
}

@Composable
private fun GitChangesTab(
    stagedFiles: List<GitFileStatus>,
    unstagedFiles: List<GitFileStatus>,
    commitMessage: String,
    onCommitMessageChange: (String) -> Unit,
    onStageFile: (GitFileStatus) -> Unit,
    onUnstageFile: (GitFileStatus) -> Unit,
    onStageAll: () -> Unit,
    onUnstageAll: () -> Unit,
    onCommit: () -> Unit,
    onStageAllAndCommit: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
        ) {
            // STAGED CHANGES SECTION
            if (stagedFiles.isNotEmpty()) {
                item(key = "staged_header") {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = 14.dp, end = 10.dp, top = 12.dp, bottom = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "STAGED CHANGES (${stagedFiles.size})",
                            style = MaterialTheme.typography.labelSmall,
                            color = Color(0xFF34D399),
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = onUnstageAll) {
                            Text("Unstage All", style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }

                items(stagedFiles, key = { "staged_${it.path}" }) { file ->
                    GitFileRow(
                        file = file,
                        staged = true,
                        onToggle = { onUnstageFile(file) },
                    )
                }
            }

            // UNSTAGED CHANGES SECTION
            if (unstagedFiles.isNotEmpty()) {
                item(key = "unstaged_header") {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = 14.dp, end = 10.dp, top = 12.dp, bottom = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "CHANGES (${unstagedFiles.size})",
                            style = MaterialTheme.typography.labelSmall,
                            color = ZedColors.DarkMuted,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = onStageAll) {
                            Text("Stage All", style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }

                items(unstagedFiles, key = { "unstaged_${it.path}" }) { file ->
                    GitFileRow(
                        file = file,
                        staged = false,
                        onToggle = { onStageFile(file) },
                    )
                }
            }

            if (stagedFiles.isEmpty() && unstagedFiles.isEmpty()) {
                item(key = "clean_state") {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(32.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                imageVector = Icons.Default.DoneAll,
                                contentDescription = null,
                                tint = Color(0xFF34D399),
                                modifier = Modifier.size(36.dp),
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = "Working tree clean",
                                style = MaterialTheme.typography.titleSmall,
                                color = ZedColors.DarkText,
                            )
                            Text(
                                text = "No uncommitted modifications",
                                style = MaterialTheme.typography.bodySmall,
                                color = ZedColors.DarkMuted,
                            )
                        }
                    }
                }
            }
        }

        HorizontalDivider(color = ZedColors.DarkHairline)

        // Commit Composer Box
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainer,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(modifier = Modifier.padding(12.dp)) {
                OutlinedTextField(
                    value = commitMessage,
                    onValueChange = onCommitMessageChange,
                    placeholder = {
                        Text(
                            "Commit message...",
                            style = MaterialTheme.typography.bodyMedium,
                            color = ZedColors.DarkMuted,
                        )
                    },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                    textStyle = TextStyle(
                        fontFamily = InterFamily,
                        fontSize = 13.5.sp,
                        color = ZedColors.DarkText,
                    ),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = MaterialTheme.colorScheme.primary,
                        unfocusedBorderColor = ZedColors.DarkHairline,
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                    ),
                    maxLines = 3,
                )

                Spacer(modifier = Modifier.height(8.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Button(
                        onClick = onCommit,
                        enabled = commitMessage.isNotBlank() && stagedFiles.isNotEmpty(),
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(8.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Commit,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("Commit", style = MaterialTheme.typography.labelMedium)
                    }

                    if (unstagedFiles.isNotEmpty() && stagedFiles.isEmpty()) {
                        FilledTonalButton(
                            onClick = onStageAllAndCommit,
                            enabled = commitMessage.isNotBlank(),
                            shape = RoundedCornerShape(8.dp),
                        ) {
                            Text("Stage All & Commit", style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun GitFileRow(
    file: GitFileStatus,
    staged: Boolean,
    onToggle: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onToggle)
            .padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(
            checked = staged,
            onCheckedChange = { onToggle() },
            colors = CheckboxDefaults.colors(
                checkedColor = Color(0xFF34D399),
                uncheckedColor = ZedColors.DarkMuted,
            ),
            modifier = Modifier.size(24.dp),
        )
        Spacer(modifier = Modifier.width(8.dp))

        // Status badge (M, A, D, ?)
        val badgeColor = when (file.status.lowercase()) {
            "modified" -> Color(0xFFFBBF24) // Yellow
            "new", "untracked" -> Color(0xFF34D399) // Green
            "deleted" -> Color(0xFFF87171) // Red
            else -> ZedColors.DarkMuted
        }
        val badgeLabel = when (file.status.lowercase()) {
            "modified" -> "M"
            "new", "untracked" -> "A"
            "deleted" -> "D"
            else -> "M"
        }

        Box(
            modifier = Modifier
                .size(18.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(badgeColor.copy(alpha = 0.2f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = badgeLabel,
                style = TextStyle(
                    fontFamily = MonoFamily,
                    fontSize = 10.5.sp,
                    fontWeight = FontWeight.Bold,
                    color = badgeColor,
                ),
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        // File Path
        Text(
            text = file.path,
            style = TextStyle(
                fontFamily = MonoFamily,
                fontSize = 12.sp,
                color = ZedColors.DarkText,
            ),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun GitGraphTab(commits: List<GitCommitInfo>) {
    if (commits.isEmpty()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "No commit history found.",
                style = MaterialTheme.typography.bodyMedium,
                color = ZedColors.DarkMuted,
            )
        }
        return
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        items(commits, key = { it.hash }) { commit ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 6.dp),
            ) {
                // Commit Graph Node & Stem
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.width(20.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.primary),
                    )
                    Box(
                        modifier = Modifier
                            .width(2.dp)
                            .height(48.dp)
                            .background(ZedColors.DarkHairline),
                    )
                }

                Spacer(modifier = Modifier.width(10.dp))

                // Commit Details
                Column(modifier = Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        // Short Hash Pill
                        Text(
                            text = commit.hash,
                            style = TextStyle(
                                fontFamily = MonoFamily,
                                fontSize = 11.5.sp,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.primary,
                            ),
                            modifier = Modifier
                                .clip(RoundedCornerShape(4.dp))
                                .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                                .padding(horizontal = 5.dp, vertical = 2.dp),
                        )

                        // Branch / Tag Decoration if present
                        if (commit.decorations.isNotBlank()) {
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(
                                text = commit.decorations.trim('(', ')', ' '),
                                style = TextStyle(
                                    fontFamily = MonoFamily,
                                    fontSize = 10.5.sp,
                                    color = Color(0xFF34D399),
                                ),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(4.dp))
                                    .background(Color(0xFF153323))
                                    .padding(horizontal = 5.dp, vertical = 2.dp),
                            )
                        }

                        Spacer(modifier = Modifier.weight(1f))

                        // Relative Time
                        Text(
                            text = commit.date,
                            style = MaterialTheme.typography.labelSmall,
                            color = ZedColors.DarkFaint,
                        )
                    }

                    Spacer(modifier = Modifier.height(4.dp))

                    // Commit Message Subject
                    Text(
                        text = commit.message,
                        style = TextStyle(
                            fontFamily = InterFamily,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium,
                            color = ZedColors.DarkText,
                        ),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )

                    // Author
                    if (commit.author.isNotBlank()) {
                        Text(
                            text = commit.author,
                            style = MaterialTheme.typography.bodySmall,
                            color = ZedColors.DarkMuted,
                        )
                    }
                }
            }
        }
    }
}
