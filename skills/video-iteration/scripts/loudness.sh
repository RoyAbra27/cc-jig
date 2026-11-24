#!/usr/bin/env bash
# Adapted from echris6/motion-video-kit (business-motion-film/scripts), MIT License, Copyright (c) 2026 echris6.
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
# documentation files, to deal in the Software without restriction, subject to the MIT License text at
# https://github.com/echris6/motion-video-kit/blob/main/LICENSE (copyright notice and permission notice kept).
# Integrated loudness, LRA, true peak, short-term per second; PASS/FAIL vs film targets.
# Usage: scripts/loudness.sh file.(mp4|mp3) [target_lufs=-14] [max_tp=-1.5]
set -euo pipefail
f="$1"; tl="${2:--14}"; mp="${3:--1.5}"
out=$(ffmpeg -hide_banner -i "$f" -af ebur128=peak=true -f null - 2>&1)
echo "$out" | grep -E "^ +(I|LRA|Peak):" | tr -s ' '
echo "short-term per second:"
echo "$out" | grep -oE "t: *[0-9.]+ .*S: *[-0-9.]+" | awk '{for(i=1;i<=NF;i++){if($i=="t:")t=$(i+1); if($i=="S:")s=$(i+1)}; if(int(t*10)%10==0) printf "%d:%s ", t, s} END{print ""}'
i=$(echo "$out" | grep -E "^ +I:" | tail -1 | awk '{print $2}')
p=$(echo "$out" | grep -E "^ +Peak:" | tail -1 | awk '{print $2}')
awk -v i="$i" -v p="$p" -v tl="$tl" -v mp="$mp" 'BEGIN{d=i-tl; if(d<0)d=-d;
 printf "RESULT integrated %s LUFS (target %s +-1): %s | true peak %s dBTP (max %s): %s\n", i, tl, (d<=1?"PASS":"FAIL"), p, mp, (p<=mp?"PASS":"FAIL")}'
