#!/usr/bin/env bash
# ==============================================================================
# Upstream Zed Fork Synchronizer
# ==============================================================================
# Keeps the `feature/mobile-gateway` branch on your GitHub fork (seeramsujay/zed)
# synchronized with the latest commits from upstream official Zed (zed-industries/zed).
# ==============================================================================

set -euo pipefail

UPSTREAM_REPO="https://github.com/zed-industries/zed.git"
FORK_REPO="https://github.com/seeramsujay/zed.git"
BRANCH="feature/mobile-gateway"
WORK_DIR="/tmp/zed-sync-workspace"

echo "======================================================================"
echo "          🔄 SYNCHRONIZING ZED FORK WITH OFFICIAL RELEASES 🔄         "
echo "======================================================================"

mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

if [[ ! -d "zed/.git" ]]; then
    echo "[*] Cloning shallow fork repository..."
    git clone --depth 50 --branch "${BRANCH}" "${FORK_REPO}" zed
    cd zed
    git remote add upstream "${UPSTREAM_REPO}"
else
    cd zed
    git remote set-url origin "${FORK_REPO}"
    if ! git remote | grep -q "^upstream$"; then
        git remote add upstream "${UPSTREAM_REPO}"
    fi
    git fetch origin "${BRANCH}"
    git checkout "${BRANCH}"
fi

echo "[*] Fetching latest commits from upstream zed-industries/zed:main..."
git fetch upstream main --depth 50

echo "[*] Rebasing ${BRANCH} on top of upstream/main..."
if git rebase upstream/main; then
    echo "[+] Rebase succeeded cleanly!"
    echo "[*] Pushing updated branch to ${FORK_REPO}..."
    git push origin "${BRANCH}" --force-with-lease
    echo "[✓] Fork synchronized successfully!"
else
    echo "[-] Merge conflict detected during rebase."
    echo "[-] Please inspect ${WORK_DIR}/zed, resolve conflicts, and run 'git rebase --continue'."
    exit 1
fi
