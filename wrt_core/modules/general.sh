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
    if [[ $COMMIT_HASH != "none" && -n "$COMMIT_HASH" ]]; then
        # 按 sha 固定版本。注意不能用 git checkout：pre_clone_action.sh 会先改
        # scripts/projectsmirrors.json（删国内镜像源），工作区是脏的，checkout 会被拒绝
        # （error: Your local changes ... would be overwritten）。
        git fetch --depth 1 origin "$COMMIT_HASH"
        git reset --hard -q FETCH_HEAD
        # reset 会把上面那次镜像清理一起冲掉，这里补回来
        if [ -f scripts/projectsmirrors.json ]; then
            sed -i '/.cn\//d; /tencent/d; /aliyun/d' scripts/projectsmirrors.json
        fi
    else
        git clean -f -d
        git reset --hard "origin/$REPO_BRANCH"
        git pull --ff-only
    fi
}
