#!/bin/zsh
# Generates the synthetic test videos used to exercise the wallpaper engine across the
# resolution / codec / aspect-ratio matrix. Requires ffmpeg with VideoToolbox.
#
#   ./Scripts/make-test-media.sh [output-directory]
#
# The clips are colour-bar patterns with a moving element, so a frozen frame, a wrong
# aspect ratio or a crop is obvious at a glance.
set -e
OUT=${1:-"${0:a:h}/../build/testmedia"}
mkdir -p "$OUT"

gen() {  # name width height seconds fps codec [audio]
  local name=$1 w=$2 h=$3 s=$4 fps=$5 codec=$6 audio=$7
  local vf="testsrc2=size=${w}x${h}:rate=${fps}:duration=${s}"
  local -a enc
  if [ "$codec" = hevc ]; then enc=(-c:v hevc_videotoolbox -tag:v hvc1 -b:v 12M)
  else enc=(-c:v h264_videotoolbox -b:v 8M); fi
  if [ -n "$audio" ]; then
    ffmpeg -y -loglevel error -f lavfi -i "$vf" -f lavfi -i "sine=frequency=440:duration=${s}" \
      "${enc[@]}" -c:a aac -shortest -pix_fmt yuv420p "$OUT/$name"
  else
    ffmpeg -y -loglevel error -f lavfi -i "$vf" "${enc[@]}" -an -pix_fmt yuv420p "$OUT/$name"
  fi
  echo "  $name"
}

echo "Writing test media to $OUT"
gen 720p_h264.mp4            1280  720  5 30 h264
gen 1080p_h264_audio.mp4     1920 1080  6 30 h264 audio
gen 1080p_hevc_60.mov        1920 1080  5 60 hevc
gen portrait_1080x1920.mov   1080 1920  5 30 hevc
gen ultrawide_3440x1440.mp4  3440 1440  5 30 hevc
gen 4k_hevc.mov              3840 2160  4 30 hevc
gen 4k_h264.mp4              3840 2160  4 30 h264
gen short_loop_2s.mp4         640  360  2 24 h264
gen long_60s.mp4             1280  720 60 30 h264
echo "Done."
