odin build demo \
    -define:FONT=/usr/share/fonts/TTF/IBMPlexMono-Light.ttf \
    -extra-linker-flags:"-L$HOME/Programming/usr/lib -Wl,-rpath=$HOME/Programming/usr/lib" \
    -debug
