#!/bin/bash

# 從 01 到 08 都跑一次
for i in 01 02 03 04 05; do
    echo ">>> Entering $i"
    cd "$i" || exit 1
    if [ -x "./03_del.sh" ]; then
        ./03_del.sh &
        echo "    Started ./03_del.sh in background (PID $!)"
    else
        echo "    Skipped: ./03_del.sh not found in $i"
    fi
    cd ..
done

echo "Waiting for all background jobs to finish..."
wait
echo "All ./03_del.sh scripts finished."