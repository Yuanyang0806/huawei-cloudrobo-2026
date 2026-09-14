#!/usr/bin/env bash

set -u

DATE="20260912"

BASE="$HOME/.cache/huggingface/lerobot/liuyy"
OUT="/tmp/lerobot_rrd_${DATE}"
LOGDIR="/tmp/lerobot_rrd_logs_${DATE}"
RESULTS="$HOME/workplace/projects/huawei-cloudrobo-2026/review_${DATE}.tsv"

mkdir -p "$OUT" "$LOGDIR"
touch "$RESULTS"

echo "============================================================"
echo "扫描 ${DATE} 今天采集的所有 LeRobot 数据集..."
echo "============================================================"

# ------------------------------------------------------------
# 自动扫描今天所有数据集，并读取 total_episodes
# 输出格式：
# dataset_name:episode_count
# ------------------------------------------------------------
mapfile -t DATASETS < <(
python - <<'PY'
from pathlib import Path
import json
import re

BASE = Path.home() / ".cache/huggingface/lerobot/liuyy"
DATE = "20260912"

pattern = re.compile(rf"^(.+)_{DATE}_(\d{{6}})$")

records = []

for d in BASE.iterdir():

    if not d.is_dir():
        continue

    m = pattern.match(d.name)

    if not m:
        continue

    info = d / "meta" / "info.json"

    if not info.exists():
        continue

    try:
        with open(info, "r", encoding="utf-8") as f:
            meta = json.load(f)

        episodes = int(meta.get("total_episodes", 0))

    except Exception:
        continue

    time_str = m.group(2)

    # 只加入真正有 episode 的数据集
    if episodes > 0:
        records.append(
            (time_str, d.name, episodes)
        )

records.sort()

for _, name, episodes in records:
    print(f"{name}:{episodes}")
PY
)

if [[ "${#DATASETS[@]}" -eq 0 ]]; then
    echo
    echo "没有发现 ${DATE} 的有效数据集。"
    exit 1
fi


echo
echo "============================================================"
echo "今天发现的有效数据集"
echo "============================================================"

TOTAL_DATASETS=0
TOTAL_EPISODES=0

for item in "${DATASETS[@]}"; do

    dataset="${item%%:*}"
    count="${item##*:}"

    printf "%-60s %4s episodes\n" "$dataset" "$count"

    TOTAL_DATASETS=$((TOTAL_DATASETS + 1))
    TOTAL_EPISODES=$((TOTAL_EPISODES + count))

done

echo "------------------------------------------------------------"
echo "有效数据集数量 : $TOTAL_DATASETS"
echo "Episode 总数   : $TOTAL_EPISODES"
echo "============================================================"


# ------------------------------------------------------------
# 展开为逐 Episode 列表
# ------------------------------------------------------------
EP_DATASETS=()
EP_NUMS=()

for item in "${DATASETS[@]}"; do

    dataset="${item%%:*}"
    count="${item##*:}"

    for ((ep=0; ep<count; ep++)); do
        EP_DATASETS+=("$dataset")
        EP_NUMS+=("$ep")
    done

done

TOTAL="${#EP_DATASETS[@]}"


# ------------------------------------------------------------
# 是否已经评价
# ------------------------------------------------------------
is_reviewed() {

    local dataset="$1"
    local ep="$2"

    awk -F'\t' \
        -v d="$dataset" \
        -v e="$ep" \
        '$1==d && $2==e && ($3=="GOOD" || $3=="BAD") {
            found=1
        }
        END {
            exit !found
        }' \
        "$RESULTS"
}


# ------------------------------------------------------------
# RRD 文件位置
# ------------------------------------------------------------
rrd_path() {

    local dataset="$1"
    local ep="$2"

    echo "$OUT/liuyy_${dataset}_episode_${ep}.rrd"
}


# ------------------------------------------------------------
# 生成一个 Episode 的 RRD
# ------------------------------------------------------------
generate_rrd() {

    local dataset="$1"
    local ep="$2"
    local file

    file="$(rrd_path "$dataset" "$ep")"

    rm -f "$file"

    lerobot-dataset-viz \
      --repo-id "liuyy/$dataset" \
      --root "$BASE/$dataset" \
      --episode-index "$ep" \
      --save 1 \
      --output-dir "$OUT" \
      --display-compressed-images \
      --num-workers 0
}


# ------------------------------------------------------------
# 找后面下一条尚未评价的 Episode
# ------------------------------------------------------------
find_next_unreviewed() {

    local start="$1"

    for ((j=start; j<TOTAL; j++)); do

        if ! is_reviewed \
            "${EP_DATASETS[$j]}" \
            "${EP_NUMS[$j]}"; then

            echo "$j"
            return
        fi

    done

    echo "-1"
}


# ------------------------------------------------------------
# 后台预加载状态
# ------------------------------------------------------------
PRELOAD_PID=""
PRELOAD_DATASET=""
PRELOAD_EP=""
PRELOAD_FILE=""
PRELOAD_LOG=""


cleanup() {

    if [[ -n "$PRELOAD_PID" ]] &&
       kill -0 "$PRELOAD_PID" 2>/dev/null; then

        kill "$PRELOAD_PID" 2>/dev/null || true
        wait "$PRELOAD_PID" 2>/dev/null || true

        if [[ -n "$PRELOAD_FILE" ]]; then
            rm -f "$PRELOAD_FILE"
        fi
    fi
}


trap cleanup EXIT INT TERM


# ------------------------------------------------------------
# 已检查数量
# ------------------------------------------------------------
DONE_COUNT=$(
awk -F'\t' \
    '$3=="GOOD" || $3=="BAD" {
        c++
    }
    END {
        print c+0
    }' \
    "$RESULTS"
)


echo
echo "============================================================"
echo " 2026-09-12 数据 Rerun 快速检查"
echo
echo " 有效数据集 : $TOTAL_DATASETS"
echo " 总 Episodes: $TOTAL"
echo " 已评价     : $DONE_COUNT"
echo
echo " 工作方式："
echo " 当前 Episode 在 Rerun 中播放"
echo " 同时后台生成下一条 Episode"
echo "============================================================"


# ------------------------------------------------------------
# 正式循环
# ------------------------------------------------------------
for ((i=0; i<TOTAL; i++)); do

    DATASET="${EP_DATASETS[$i]}"
    EP="${EP_NUMS[$i]}"

    CURRENT=$((i + 1))

    # 已经检查过的直接跳过
    if is_reviewed "$DATASET" "$EP"; then

        echo \
        "[$CURRENT/$TOTAL] 已检查，跳过: $DATASET ep$EP"

        continue
    fi


    FILE="$(rrd_path "$DATASET" "$EP")"


    echo
    echo "============================================================"
    echo " [$CURRENT / $TOTAL]"
    echo
    echo " Dataset : $DATASET"
    echo " Episode : $EP"
    echo "============================================================"


    # --------------------------------------------------------
    # 如果当前 Episode 正是上一轮后台生成的那个
    # --------------------------------------------------------
    if [[ -n "$PRELOAD_PID" &&
          "$PRELOAD_DATASET" == "$DATASET" &&
          "$PRELOAD_EP" == "$EP" ]]; then

        if kill -0 "$PRELOAD_PID" 2>/dev/null; then
            echo "[等待] 当前 Episode 后台生成尚未完成..."
        else
            echo "[预加载] 当前 Episode 已经生成完成。"
        fi

        if ! wait "$PRELOAD_PID"; then

            echo
            echo "后台生成失败。最后日志："
            echo "------------------------------------------------------------"

            tail -n 40 "$PRELOAD_LOG" 2>/dev/null || true

            echo "------------------------------------------------------------"

            rm -f "$FILE"
        fi

        PRELOAD_PID=""
        PRELOAD_DATASET=""
        PRELOAD_EP=""
        PRELOAD_FILE=""
        PRELOAD_LOG=""
    fi


    # --------------------------------------------------------
    # 如果没有缓存，前台生成
    # --------------------------------------------------------
    if [[ ! -s "$FILE" ]]; then

        echo
        echo "[准备当前条]"
        echo "正在生成 RRD..."

        if ! generate_rrd "$DATASET" "$EP"; then

            echo
            echo "❌ RRD 生成失败"
            echo "$DATASET ep$EP"

            read -rp "按 Enter 跳过该 Episode..."

            continue
        fi

    else

        echo
        echo "[准备当前条]"
        echo "✅ 已预加载完成，无需重新生成。"

    fi


    # --------------------------------------------------------
    # 提前找下一条尚未评价的数据
    # --------------------------------------------------------
    NEXT_INDEX="$(find_next_unreviewed $((i + 1)))"


    if [[ "$NEXT_INDEX" -ge 0 ]]; then

        NEXT_DATASET="${EP_DATASETS[$NEXT_INDEX]}"
        NEXT_EP="${EP_NUMS[$NEXT_INDEX]}"

        NEXT_FILE="$(rrd_path "$NEXT_DATASET" "$NEXT_EP")"


        if [[ ! -s "$NEXT_FILE" ]]; then

            PRELOAD_DATASET="$NEXT_DATASET"
            PRELOAD_EP="$NEXT_EP"
            PRELOAD_FILE="$NEXT_FILE"

            PRELOAD_LOG="$LOGDIR/${NEXT_DATASET}_ep${NEXT_EP}.log"


            echo
            echo "[后台预加载]"
            echo "下一条:"
            echo "  $NEXT_DATASET"
            echo "  Episode $NEXT_EP"


            (
                nice -n 5 \
                lerobot-dataset-viz \
                  --repo-id "liuyy/$NEXT_DATASET" \
                  --root "$BASE/$NEXT_DATASET" \
                  --episode-index "$NEXT_EP" \
                  --save 1 \
                  --output-dir "$OUT" \
                  --display-compressed-images \
                  --num-workers 0 \
                  >"$PRELOAD_LOG" 2>&1
            ) &

            PRELOAD_PID=$!

        else

            echo
            echo "[后台预加载]"
            echo "✅ 下一条已经存在缓存。"

        fi
    fi


    # --------------------------------------------------------
    # 打开当前 Episode
    # --------------------------------------------------------
    echo
    echo "============================================================"
    echo "[打开 Rerun]"
    echo
    echo "当前:"
    echo "  $DATASET"
    echo "  Episode $EP"
    echo
    echo "你查看当前数据时，下一条正在后台生成。"
    echo "============================================================"
    echo


    rerun "$FILE"


    # --------------------------------------------------------
    # 人工评价
    # --------------------------------------------------------
    while true; do

        echo
        echo "============================================================"
        echo "评价当前 Episode"
        echo
        echo " g = GOOD"
        echo "     数据正常，可以用于训练"
        echo
        echo " b = BAD"
        echo "     数据异常，不用于训练"
        echo
        echo " r = Replay"
        echo "     再看一次"
        echo
        echo " s = Skip"
        echo "     暂时跳过"
        echo
        echo " q = Quit"
        echo "     保存当前进度并退出"
        echo "============================================================"

        read -rp "> " CHOICE


        case "$CHOICE" in

            g|G)

                printf "%s\t%s\tGOOD\n" \
                    "$DATASET" \
                    "$EP" \
                    >> "$RESULTS"

                echo
                echo "✅ 已标记 GOOD"

                # 已经评价完成，释放 RRD
                rm -f "$FILE"

                break
                ;;


            b|B)

                printf "%s\t%s\tBAD\n" \
                    "$DATASET" \
                    "$EP" \
                    >> "$RESULTS"

                echo
                echo "❌ 已标记 BAD"

                rm -f "$FILE"

                break
                ;;


            r|R)

                echo
                echo "重新打开当前 Episode..."

                rerun "$FILE"
                ;;


            s|S)

                echo
                echo "暂时跳过。"
                echo "下次运行仍会检查这一条。"

                # 保留 RRD
                break
                ;;


            q|Q)

                echo
                echo "============================================================"
                echo "检查中止"
                echo
                echo "GOOD/BAD 记录已保留："
                echo "$RESULTS"
                echo
                echo "下次运行相同脚本会自动继续。"
                echo "============================================================"

                exit 0
                ;;


            *)

                echo "请输入 g / b / r / s / q"
                ;;

        esac

    done

done


# ------------------------------------------------------------
# 最终统计
# ------------------------------------------------------------
echo
echo "============================================================"
echo "全部数据检查完成"
echo "============================================================"


GOOD=$(
awk -F'\t' \
    '$3=="GOOD" {
        c++
    }
    END {
        print c+0
    }' \
    "$RESULTS"
)


BAD=$(
awk -F'\t' \
    '$3=="BAD" {
        c++
    }
    END {
        print c+0
    }' \
    "$RESULTS"
)


echo "TOTAL : $TOTAL"
echo "GOOD  : $GOOD"
echo "BAD   : $BAD"

echo
echo "完整评价结果："
echo

column -t -s $'\t' "$RESULTS"

echo
echo "评价文件："
echo "$RESULTS"

