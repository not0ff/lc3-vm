# lc3-vm
A virtual machine for LC-3 educational computer.
Made with the help of [a great guide](https://www.jmeiners.com/lc3-vm/) by Justin Meiners and Ryan Pendleton

## Usage
Provide assembled images as cli args
```
$ ./lc3 examples/hello.obj
```

## Compiling
Build with Zig 0.16.0
```
$ zig build -Drelease=true
```

## How to get .obj files
You can create "image" files using *lc3as* assembler found in [here](https://github.com/haplesshero13/lc3tools). There is also a c compiler available called [lcc-lc3](https://github.com/haplesshero13/lcc-lc3) though I couldn't get it to build on my system.

## License
Licensed under GPLv3

## References
- https://www.jmeiners.com/lc3-vm/
- https://www.jmeiners.com/lc3-vm/supplies/lc3-isa.pdf
- https://en.wikipedia.org/wiki/Little_Computer_3
