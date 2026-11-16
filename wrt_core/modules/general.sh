#!/usr/bin/env bash
# Module: General Preparation

clone_repo() {
    if [[ ! -d $BUILD_DIR ]]; then
        echo "克隆仓库: $REPO_URL 分支: $REPO_BRANCH"
        if [ "$COMMIT_HASH" != "none" ] && [ -n "$COMMIT_HASH" ]; then
            # 指定了 COMMIT_HASH 时按 sha 浅取，避免 --depth 1 之后 checkout 老 commit 失败
            mkdir -p "$BUILD_DIR"
            git -C "$BUILD_DIR" init -q
            git -C "$BUILD_DIR" remote add origin "$REPO_URL"
            if ! git -C "$BUILD_DIR" fetch --depth 1 origin "$COMMIT_HASH"; then
                echo "错误：拉取 $REPO_URL 的 $COMMIT_HASH 失败" >&2
                exit 1
            fi
            git -C "$BUILD_DIR" checkout -q FETCH_HEAD
        elif ! git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR; then
            echo "错误：克隆仓库 $REPO_URL 失败" >&2
            exit 1
        fi
    fi
}

clean_up() {
    if [[ ! -d "$BUILD_DIR" ]]; then
        echo "Build directory $BUILD_DIR does not exist"
        return
    fi
    cd "$BUILD_DIR"
    if [[ -f ".config" ]]; then
        \rm -f ".config"
    fi
    if [[ -d "tmp" ]]; then
        \rm -rf "tmp"
    fi
    if [[ -d "logs" ]]; then
        \rm -rf "logs/*"
    fi
    if [[ -d "feeds" ]]; then
        ./scripts/feeds clean
    fi
    mkdir -p "tmp"
    echo "1" >"tmp/.build"
}

reset_feeds_conf() {
    git clean -f -d
    if [[ $COMMIT_HASH != "none" && -n "$COMMIT_HASH" ]]; then
        # 按 sha 固定版本：重新拉取同一个 commit 并检出（不跟随分支头）
        git fetch --depth 1 origin "$COMMIT_HASH"
        git checkout -q FETCH_HEAD
    else
        git reset --hard "origin/$REPO_BRANCH"
        git pull --ff-only
    fi
}
