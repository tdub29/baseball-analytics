#!/usr/bin/env bash
# Batted balls from Baseball Savant (key-free), one CSV per week, regular season 2015-2025.
# Resumable: a week already on disk with rows is skipped. Exit velocity, launch angle and Savant's
# expected wOBA per ball, for expected-outcome rates in the matchup model (MATCHUP-PLAN.md).
#   bash research/r/mlb/fetch_statcast.sh 2015 2025
set -u
out="data/mlb/raw/statcast"; mkdir -p "$out"
bbt="fly%5C.%5C.ball%7Cground%5C.%5C.ball%7Cline%5C.%5C.drive%7Cpopup%7C"
for y in $(seq "$1" "$2"); do
  [ "$y" = 2020 ] && start="$y-07-20" || start="$y-03-15"
  d="$start"
  while [[ "$d" < "$y-11-05" ]]; do
    e=$(date -d "$d + 6 days" +%F)
    f="$out/bip_${d}.csv"
    if [ ! -s "$f" ] || [ "$(wc -l < "$f")" -lt 2 ]; then
      curl -s --retry 3 --max-time 120 -o "$f" \
        "https://baseballsavant.mlb.com/statcast_search/csv?all=true&hfGT=R%7C&hfSea=$y%7C&player_type=batter&game_date_gt=$d&game_date_lt=$e&hfBBT=$bbt&type=details"
      sleep 1
    fi
    d=$(date -d "$d + 7 days" +%F)
  done
  echo "$y done: $(cat "$out"/bip_"$y"-*.csv 2>/dev/null | wc -l) lines"
done
