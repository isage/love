#!/bin/bash
platform/vita/automagic

./configure --host=arm-vita-eabi  --prefix=$VITASDK/arm-vita-eabi/ --disable-shared --enable-static --with-luaversion=5.1 --disable-library-enet --disable-library-luasocket

make -j 6

vita-elf-create -s ./src/love ./love.velf
vita-make-fself ./love.velf ./love.self

