# Security Policy

MintApp Remover is a script for local use: if you find a real problem or security flaw, report it privately instead of opening a public issue.

## How to report it

Write to **filonux@proton.me** with a description of the problem and, if you can, the steps to reproduce it. Add your distribution and the output of `MintApp_Remover.sh --version`.

## What counts

The script runs package-manager commands, and removes files in some entries of the deep cleanup, with administrator rights. These are security problems:

- Anything that makes it remove or run something other than what it showed you on screen.
- Anything that exposes the administrator password you type in its password window.

A wrong text or a window that does not fit is not one: open a normal issue for those.
