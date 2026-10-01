#!/usr/bin/env bash
# Builds a synthetic Audiobookshelf library (no live data) for the browser client's real-server QA.
# Requires local ffmpeg, calibre's ebook-convert, rar and zip. Output: qa/.runtime/library/{books,podcasts}
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)/.runtime/library"
stamp="$root/.complete-v2"
if [[ -f "$stamp" ]]; then
  echo "$root"
  exit 0
fi
rm -rf "$root"
books="$root/books"
podcasts="$root/podcasts"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$books" "$podcasts"

tone() { # file seconds frequency title artist album track genre
  ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=$3:sample_rate=22050:duration=$2" -ac 1 \
    -metadata title="$4" -metadata artist="$5" -metadata album="$6" -metadata track="$7" -metadata genre="$8" \
    -c:a libmp3lame -b:a 48k "$1"
}
cover() { # file width height colour
  ffmpeg -loglevel error -y -f lavfi -i "color=c=$4:s=$2x$3" -frames:v 1 "$1"
}

# 1. Multi-file audiobook with a PDF companion and tall cover.
dir="$books/Mira Vale/Harbor Lights/Book 1 - The Long Tide"
mkdir -p "$dir"
tone "$dir/01 - Arrival.mp3" 30 330 "Arrival" "Mira Vale" "The Long Tide" 1 "Fiction"
tone "$dir/02 - Crossing.mp3" 30 440 "Crossing" "Mira Vale" "The Long Tide" 2 "Fiction"
tone "$dir/03 - Landfall.mp3" 30 550 "Landfall" "Mira Vale" "The Long Tide" 3 "Fiction"
cover "$dir/cover.jpg" 400 600 "#1f5f8b"
printf 'A harbor town waits for a ship that left a decade ago. Synthetic QA audiobook in three files.' >"$dir/desc.txt"
printf 'QA Narrator' >"$dir/reader.txt"
python3 "$(dirname "$0")/make-pdf.py" "$dir/The Long Tide Companion.pdf" 12 "The Long Tide Companion"

# 2. Single-file M4B with embedded chapters and a square cover.
dir="$books/Mira Vale/Harbor Lights/Book 2 - Salt and Signal"
mkdir -p "$dir"
cat >"$work/chapters.txt" <<'META'
;FFMETADATA1
title=Salt and Signal
artist=Mira Vale
album=Salt and Signal
genre=Mystery
[CHAPTER]
TIMEBASE=1/1000
START=0
END=20000
title=The Lighthouse
[CHAPTER]
TIMEBASE=1/1000
START=20000
END=40000
title=Morse at Midnight
[CHAPTER]
TIMEBASE=1/1000
START=40000
END=60000
title=Dawn Tide
META
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=392:sample_rate=22050:duration=60" -i "$work/chapters.txt" \
  -map_metadata 1 -map_chapters 1 -ac 1 -c:a aac -b:a 48k "$dir/Salt and Signal.m4b"
cover "$dir/cover.jpg" 500 500 "#8b3a1f"

# 3. Long title, no cover, a single file.
dir="$books/Jon Archer/A Very Long Story Title About Finding Your Way Home Through A City Of Unexpected Doors"
mkdir -p "$dir"
tone "$dir/part.mp3" 20 262 "A Very Long Story Title About Finding Your Way Home Through A City Of Unexpected Doors" "Jon Archer" "A Very Long Story Title" 1 "Fantasy"

# 4. Ebook-only items in every browser reader format.
cat >"$work/paper.html" <<'HTML'
<html><head><title>Paper Lanterns</title><meta name="author" content="Ada North"></head><body>
HTML
for chapter in 1 2 3 4 5 6; do
  {
    printf '<h1 class="chapter">Chapter %s: Lantern %s</h1>\n' "$chapter" "$chapter"
    for paragraph in $(seq 1 40); do
      printf '<p>Passage %s.%s. The lanterns along the canal flickered as the paper boats drifted past the old mill, carrying wishes written in careful ink.</p>\n' "$chapter" "$paragraph"
    done
  } >>"$work/paper.html"
done
printf '</body></html>' >>"$work/paper.html"
mkdir -p "$books/Ada North/Paper Lanterns" "$books/Ada North/Night Ferry" "$books/Ada North/Glass Orchard" "$books/Ada North/Field Guide to Quiet"
ebook-convert "$work/paper.html" "$books/Ada North/Paper Lanterns/Paper Lanterns.epub" --title "Paper Lanterns" --authors "Ada North" \
  --chapter "//h:h1" --level1-toc "//h:h1" >/dev/null
sed -e 's/Paper Lanterns/Night Ferry/g' -e 's/lanterns along the canal/ferry lights on the river/g' "$work/paper.html" >"$work/ferry.html"
ebook-convert "$work/ferry.html" "$books/Ada North/Night Ferry/Night Ferry.mobi" --title "Night Ferry" --authors "Ada North" \
  --chapter "//h:h1" --level1-toc "//h:h1" >/dev/null
sed -e 's/Paper Lanterns/Glass Orchard/g' -e 's/lanterns along the canal/glass apples in the orchard/g' "$work/paper.html" >"$work/orchard.html"
ebook-convert "$work/orchard.html" "$books/Ada North/Glass Orchard/Glass Orchard.azw3" --title "Glass Orchard" --authors "Ada North" \
  --chapter "//h:h1" --level1-toc "//h:h1" >/dev/null
python3 "$(dirname "$0")/make-pdf.py" "$books/Ada North/Field Guide to Quiet/Field Guide to Quiet.pdf" 120 "Field Guide to Quiet"

for issue in 1 2; do
  mkdir -p "$work/comic$issue"
  for page in 1 2 3 4 5 6 7 8 9 10 11 12; do
    ffmpeg -loglevel error -y -f lavfi -i "color=c=0x$(printf '%02x%02x%02x' $((page * 20)) 90 $((200 - page * 10))):s=600x900" \
      -vf "drawbox=x=40:y=40:w=520:h=$((60 * page)):color=white@0.8:t=fill" -frames:v 1 "$work/comic$issue/page $page.png"
  done
  printf '<?xml version="1.0"?><ComicInfo><Title>Skyline Issue %s</Title><Series>Skyline</Series><Number>%s</Number><Writer>Rin Okada</Writer></ComicInfo>' "$issue" "$issue" >"$work/comic$issue/ComicInfo.xml"
  mkdir -p "$books/Rin Okada/Skyline Issue $issue"
done
(cd "$work/comic1" && zip -q -0 "$books/Rin Okada/Skyline Issue 1/Skyline Issue 1.cbz" ./*.png ComicInfo.xml)
(cd "$work/comic2" && rar a -idq "$books/Rin Okada/Skyline Issue 2/Skyline Issue 2.cbr" ./*.png ComicInfo.xml)

# 5. Filler audiobooks so the catalog paginates (> 2 pages of 24).
tone "$work/filler.mp3" 4 220 "Filler" "Catalog Author" "Filler" 1 "Reference"
for n in $(seq -w 1 60); do
  dir="$books/Catalog Author/Catalog Volume $n"
  mkdir -p "$dir"
  ffmpeg -loglevel error -y -i "$work/filler.mp3" -c copy -metadata title="Catalog Volume $n" -metadata album="Catalog Volume $n" \
    -metadata artist="Catalog Author" -metadata genre="Reference" "$dir/Catalog Volume $n.mp3"
done

# 6. Podcast with dated episodes.
dir="$podcasts/Evening Stories"
mkdir -p "$dir"
cover "$dir/cover.jpg" 600 600 "#3b2f7a"
for episode in 1 2 3 4; do
  ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=$((300 + episode * 40)):sample_rate=22050:duration=25" -ac 1 \
    -metadata title="Episode $episode: Evening $episode" -metadata artist="QA Studio" -metadata album="Evening Stories" \
    -metadata date="2026-09-0$episode" -metadata track="$episode" -metadata genre="Podcast" \
    -c:a libmp3lame -b:a 48k "$dir/Episode $episode.mp3"
done

touch "$stamp"
echo "$root"
