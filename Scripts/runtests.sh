#!/bin/zsh
# Runs the test suite with a hard wall-clock limit so a symbolication hang in the Xcode
# harness cannot block indefinitely.
ROOT="${0:a:h}/.."
LIMIT=${LIMIT:-420}
OUT=${OUT:-/tmp/lc-tests.txt}
shift_args=("$@")
xcodebuild -project "$ROOT/LiveCanvas.xcodeproj" -scheme LiveCanvas -configuration Debug \
  -derivedDataPath "$ROOT/build/DerivedData" "${shift_args[@]}" > "$OUT" 2>&1 &
PID=$!
SECS=0
while kill -0 $PID 2>/dev/null; do
  sleep 3; SECS=$((SECS+3))
  if [ $SECS -ge $LIMIT ]; then
    echo "TIMEOUT after ${LIMIT}s — killing"
    kill -9 $PID 2>/dev/null; pkill -9 xctest 2>/dev/null; pkill -9 -x LiveCanvas 2>/dev/null
    break
  fi
done
wait $PID 2>/dev/null
grep -E "error:|TEST (SUCCEEDED|FAILED)|BUILD (SUCCEEDED|FAILED)" "$OUT" | sed 's/ on .My Mac.*//' | sort -u
# Match the status word only at the end of the line: test NAMES can contain "failed".
echo "--- unique passed: $(grep -E "^Test case '[^']+' passed" "$OUT" | sed 's/ on .My Mac.*//' | sort -u | wc -l | tr -d ' ')"
echo "--- unique failed: $(grep -E "^Test case '[^']+' failed" "$OUT" | sed 's/ on .My Mac.*//' | sort -u | wc -l | tr -d ' ')"
grep -E "^Test case '[^']+' failed" "$OUT" | sed 's/ on .My Mac.*//' | sort -u
