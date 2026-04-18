xcrun -sdk macosx metal -c src/kernel.metal -o src/kernel.air
xcrun -sdk macosx metallib src/kernel.air -o src/default.metallib
