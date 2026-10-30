#!/bin/zsh
# Regenerates the README screenshots and GIFs from the real plugin running in omarchy-shell.
# Run with: zsh media/record/make_media.sh   (needs wf-recorder, ydotool with ydotoold running, ffmpeg, node)
# It takes over the screen for ~5 minutes on an empty workspace (9) with sample data in ~/.cache/houra-demo,
# then restarts omarchy-shell on your own data. Coordinates assume a 1920x1080 panel at scale 1.25.
set -eu
. ${0:A:h}/lib.sh
CLIPS=$REPO/media/public/clips
mkdir -p $CLIPS $REPO/assets $DEMO/{data,config,cache,state} ~/Notes
NOTES_CREATED=0; [ -e "$HOME/Notes/Week $(date +%V).md" ] || NOTES_CREATED=1

cat > $DEMO/env <<EOF
HOURA_LANG=en
HOURA_DB=$DEMO/data/houra.sqlite
HOURA_CONFIG=$DEMO/config/settings.json
HOURA_CACHE_DIR=$DEMO/cache
HOURA_STATE_DIR=$DEMO/state
HOURA_TODOIST_API_BASE=http://127.0.0.1:8765/api/v1
EOF
# Sample Todoist account (never the real API)
python3 -I ${0:A:h}/mock_todoist.py 8765 & MOCK=$!
trap 'kill $MOCK 2>/dev/null || true' EXIT INT TERM
cp ${0:A:h}/doc.html $DEMO/doc.html
[ $NOTES_CREATED = 1 ] && cp ${0:A:h}/week.md "$HOME/Notes/Week $(date +%V).md"

# A calm "document" window behind the timer, like the macOS README scene
hyprctl dispatch "hl.dsp.focus({monitor=\"$MON\"})" >/dev/null
hyprctl dispatch 'hl.dsp.focus({workspace=9})' >/dev/null
hyprctl dispatch "hl.dsp.exec_cmd(\"brave --user-data-dir=$DEMO/brave --no-first-run --no-default-browser-check --app=file://$DEMO/doc.html\")" >/dev/null
sleep 4

rec_start() { wf-recorder -y -o $MON -r 30 -f $CLIPS/$1.mp4 >/dev/null 2>&1 & RP=$!; sleep 1.2; }
rec_stop() { sleep 0.5; kill -INT $RP; wait $RP 2>/dev/null || true; }
# Houra windows are centred; crop rectangles are physical pixels
shot() { grim -o $MON - | ffmpeg -v error -y -i - -vf "crop=$2" $REPO/assets/$1.png; }

sc_flow() {
  fresh tag; mv_ 1300 880; sleep 0.5
  rec_start flow
  omarchy-shell houra newSession >/dev/null; sleep 1.2
  glide 1300 880 960 308 18; click 960 308; sleep 0.2
  ydotool type -d 55 "Ship the onboarding tour" >/dev/null; sleep 0.5
  glide 960 308 670 426 12; click 670 426; sleep 0.5
  glide 670 426 670 464 6; click 670 464; sleep 0.6
  glide 670 464 800 663 12; click 800 663; sleep 0.7
  glide 800 663 1187 915 14; click 1187 915; sleep 1.6
  glide 1187 915 1760 498 24; click 1760 498; sleep 2.2
  glide 1760 498 1238 592 18; click 1238 592; sleep 1.4
  glide 1238 592 1518 426 14; sleep 0.3; click 1518 426; sleep 4
  rec_stop
}

sc_widgets() {
  fresh tag; mv_ 1300 880; start_quick "Polish the pricing page"; mv_ 1100 800; sleep 1
  rec_start widgets
  sleep 1.5; glide 1100 800 1760 498 20; click 1760 498; sleep 2.4
  glide 1760 498 900 700 18; sleep 0.8
  omarchy-shell houra style strip >/dev/null; sleep 2.4
  omarchy-shell houra style capsule >/dev/null; sleep 1.6
  glide 900 700 1675 1006 20; click 1675 1006; sleep 2.4
  glide 1675 1006 900 700 18; sleep 0.8
  omarchy-shell houra style card >/dev/null; sleep 2.4
  omarchy-shell houra style ring >/dev/null; sleep 1.6
  glide 900 700 1838 994 20; click 1838 994; sleep 2.4
  glide 1838 994 900 700 18; sleep 1
  rec_stop
}

sc_snap() {
  fresh tag; mv_ 1300 880; start_quick "Draft the plugin docs"; mv_ 1100 600; sleep 1
  rec_start snap
  sleep 1; glide 1100 600 1800 498 18; sleep 0.4
  ydotool click 0x40 >/dev/null; sleep 0.2
  glide 1800 498 1500 520 10; glide 1500 520 300 560 40; glide 300 560 120 560 8
  ydotool click 0x80 >/dev/null; sleep 1.6
  glide 120 560 900 650 20; sleep 1.2
  rec_stop
}

sc_rest() {
  fresh tag; mv_ 1300 880; start_quick "Finish chapter 7"; mv_ 1700 1000; sleep 1
  omarchy-shell houra finish >/dev/null; sleep 2.5
  rec_start rest
  sleep 7
  rec_stop
}

sc_stats() {
  fresh tag; mv_ 1880 1050; sleep 0.5
  omarchy-shell houra panel >/dev/null; sleep 0.6; omarchy-shell houra tab stats >/dev/null; sleep 1.5
  rec_start stats
  sleep 1.2
  glide 1880 1050 1502 344 20; click 1502 344; sleep 2.2
  glide 1502 344 1577 344 8; click 1577 344; sleep 2.2
  glide 1577 344 1428 344 8; click 1428 344; sleep 1.2
  glide 1428 344 660 698 22; sleep 1.6
  glide 660 698 660 758 6; sleep 1.4
  glide 660 758 1222 151 22; click 1222 151; sleep 2.2
  glide 1222 151 1290 151 6; click 1290 151; sleep 2.4
  glide 1290 151 1155 151 6; click 1155 151; sleep 1.2
  rec_stop
}

sc_todoist() {
  fresh tag todoist; mv_ 1300 880; sleep 0.5
  rec_start todoist
  omarchy-shell houra newSession >/dev/null; sleep 1.2
  glide 1300 880 960 308 18; click 960 308; sleep 0.2
  ydotool type -d 55 "Polish onboarding" >/dev/null; sleep 0.4
  glide 960 308 753 374 10; click 753 374; sleep 1.2
  glide 753 374 670 386 6; click 670 386; sleep 0.5
  glide 670 386 670 425 4; click 670 425; sleep 0.6
  glide 670 425 800 558 8; click 800 558; sleep 0.2
  ydotool type -d 45 "Record the demo video p2 @16:00" >/dev/null; sleep 0.4
  glide 800 558 897 600 8; click 897 600; sleep 0.6
  glide 897 600 1256 558 10; click 1256 558; sleep 1.2
  glide 1256 558 1187 975 14; click 1187 975; sleep 1.6
  glide 1187 975 1760 498 20; click 1760 498; sleep 2.2
  glide 1760 498 1455 703 16; click 1455 703; sleep 2.6
  glide 1455 703 1455 830 8; sleep 1.2
  rec_stop
}

sc_stills() {
  fresh tag; mv_ 1900 1060
  omarchy-shell houra newSession >/dev/null; sleep 1.2; shot new-session "692:834:614:140"
  omarchy-shell houra close >/dev/null; sleep 0.5
  omarchy-shell houra panel >/dev/null; sleep 0.8
  for t in today stats sessions categories settings; do
    omarchy-shell houra tab $t >/dev/null; sleep 1.3; mv_ 1900 1060; shot panel-$t "1404:929:258:92"
  done
  omarchy-shell houra close >/dev/null
}

for s in ${@:-flow widgets snap rest stats todoist stills}; do sc_$s; done

# Back to your own data, notifications and workspace
for a in $(hyprctl clients -j | python3 -c 'import json,sys;[print(c["address"]) for c in json.load(sys.stdin) if "houra-demo" in c["class"]]'); do
  hyprctl dispatch "hl.dsp.window.close({window=\"address:$a\"})" >/dev/null
done
[ $NOTES_CREATED = 1 ] && rm -f "$HOME/Notes/Week $(date +%V).md" && rmdir ~/Notes 2>/dev/null || true
omarchy-restart-shell >/dev/null 2>&1
sleep 4; [ "$(omarchy-shell notifications toggleDnd 2>/dev/null)" = "off" ] || omarchy-shell notifications toggleDnd >/dev/null

kill $MOCK 2>/dev/null || true
cd $REPO/media && node render.mjs
