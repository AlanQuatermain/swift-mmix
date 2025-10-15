# MIX & MMIX in Swift

I've long been a fan of [The Art of Computer Programming](https://en.wikipedia.org/wiki/The_Art_of_Computer_Programming), in particular the way it uses low-level assembly to show how to implement, evaluate, and optimize algorithms. While we live in a time of high-level languages, I've found that understanding the actual instruction stream produced by these languages' compilers is itself fundamental to understanding how to best tailor our work. Knowledge of things like call stacks, register saving, and the differences between working with memory vs. registers are all integral to how I do my work, even when I work in something like Swift (which is several levels further from the instruction stream than, say C or Pascal).

Donald Knuth's designs of the 1960's-style CISC [MIX computer](https://en.wikipedia.org/wiki/MIX_%28abstract_machine%29) and its more modern RISC [MMIX computer](https://en.wikipedia.org/wiki/MMIX) are each useful in learning how computers (yes, even modern ones) function. While MMIX is clearly closer to modern CPUs with its many registers, 8-bit byte-addressable memory, and reduced instruction set, the older MIX computer provides both a handy stepping-stone and an important reminder that not everything needs to be the way it is today:

1. The CISC instruction set is arguably easier to learn, since its instructions are higher-level, each performing a complex but easily-defined task as a whole.
2. Using sign + magnitude numeric representation rather than twos-complement is easier for a human to read, which helps with gaining that initial understanding of what you're looking at (the number went negative? by how much? is that -342? hang on, let me do some twos-complement math to figure that out...)
3. The use of 6-bit bytes and 5-byte words helps to un-tether the reader's expectations from the current status-quo of universal 8-bit bytes, and makes us think in different ways about how we deal with numerics and data. Think of it as exercise for the brain.
4. Those of us who came into computer programming during the Intel-dominated era had a fairly easy instruction set to learn and understand (i32 and later i64). While we don't see that as often now (ARM is everywhere these days), Intel assembly and its mnemonics were often easy to understand at a glance, and that understanding enabled us to better understand the RISC instructions on PowerPC or ARM processors today.

It's long been a dream of mine to build something from whole-cloth that would provide a means of visualizing exactly how Knuth's algorithms operated on their target computers. Originally using MIX (I first picked up TAoCP before Volume 4A was released), and now with MMIX, I felt it would greatly aid me personally in understanding the lessons imparted through the books. If it would help me, it would likely help others, too. And if it would help me to have that tool, I would surely learn much more by actually *creating* it.

This has been an itch I've had no time to scratch, alas, for over 20 years now. With the advent of tools like ChatGPT, Codex, and Claude, however, I now have an assistant to help me get the pieces together, and keep me on the right track. When I need to know something about designing VMs, I can ask about that. When I need to quickly understand how certain things work in certain conditions, I can ask about *that*, too. As a result I've been able to put together a fairly comprehensive set of documents describing how to create the toolset I'd like to see.

Crucially, I'd like the visualization part to be the primary way we see the programs that run. Debuggers have the ability to show memory and registers, but these are provided as reference: mostly you're focusing on the code. I'd like to focus on what the machine is doing at least as much. Imagine you're working with Babbage's Analytical Engine and you'll see what I mean: there are a bunch of levers and pistons moving around in there, but how do they relate to the abstract calculations going on? I'd like this tool to provide that link, and to teach that kind of visualization.

## The Architecture

The library is built on a core framework called **MachineKit**, which provides the fundamental abstractions for any computer architecture: machine words, memory spaces, register files. On top of this sit the **MIXArchitecture** and **MMIXArchitecture** modules, implementing the specifics of each system.

### MIX

MIX is disarmingly anachronistic---it uses sign-magnitude representation rather than two's-complement, it has 6-bit bytes (values 0-63), five-byte words, and uses field specifications to address partial words. It's a product of its era, but that's part of its value: it teaches you to think outside of the modern representations we now use, which in turn leads you to a more flexible way of thinking and a deeper understanding of the solutions.

### MMIX

MMIX is MIX's modern counterpart: 64-bit registers, byte-addressable memory, two's-complement arithmetic. It's a clean, elegant RISC design that could plausibly exist in hardware. Working with MMIX gives you insight into contemporary computer architecture while maintaining that crucial connection to Knuth's algorithmic analyses.

## What's Next

Right now the foundation is in place. The numeric types are in place, memory management works, the basic infrastructure is solid. What comes next is the fun part: instruction execution, program loading, and ultimately, the graphical tools themselves.

I want to build something where you can load a MIX or MMIX program, set breakpoints, step through it line by line, and watch exactly what's happening in the machine's state. Watch the call stack grow as functions call other functions. See registers being saved and restored. Understand how local variables actually live in memory or registers. Crucially, this is all intended to be the *primary* means of visualization and interaction with the algorithms and programs.

The ultimate goal is to make these algorithms—these fundamental building blocks of computer science—truly comprehensible. Not just intellectually, but viscerally. To create that moment of "oh, *that's* how it works" that's so much harder to achieve with traditional teaching methods.

## Current Status

**Milestone 2: Core Data Types & Memory** is complete. The numeric types for both MIX and MMIX are fully implemented and tested, including:

- MIX: Sign-magnitude words, field specifications, byte operations, arithmetic with overflow detection
- MMIX: Byte, Wyde, Tetra, and Octa types with full two's-complement arithmetic
- Memory systems for both architectures with proper field-aware operations for MIX

The test suite is comprehensive—103 tests covering everything from basic arithmetic to double-word shifts and rotations. The foundation is solid.

Next up: instruction decoding and execution. Then we start building the tools that make all of this *visible*.

### Remaining Milestones

1. ~~Setup~~
2. ~~Core Data Types & Memory~~
3. **Instruction Set Definition**
4. **Execution Engine**
5. **Assembler & Disassembler**
6. **Command-Line Tooling**
7. **Debugger & Introspection Enhancements**
8. **GUI Exploration**

## Why Swift?

I'm building this in Swift for a few reasons. First, it's the language I know best, and building something like this requires enough mental bandwidth that I don't want to be fighting the language. Second, because my ultimate goal involves graphical tools, and as I'm an engineer on the SwiftUI project, SwiftUI is the most logical tool for the job---which again means the use of Swift. Start as you mean to go on, and all that.

## Contributing

This is an early-stage project, and I'm very much finding my way as I go. If you're interested in contributing, or if you have ideas about how to make these visualizations more effective, I'd love to hear from you. The goal is to make computer science education better, and that's something we could all benefit from.

---

*"The real problem is that programmers have spent far too much time worrying about efficiency in the wrong places and at the wrong times; premature optimization is the root of all evil (or at least most of it) in programming."*
— Donald E. Knuth
