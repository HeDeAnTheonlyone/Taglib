# Taglib Tools
Here are all the tools for taglib and working with tags in general.

- <ins>**Tag dereferencer**</ins><br>
    This tool simplifies to create easy to work with tags by dereferencing all tag references. It replaces the reference with the entries in the referenced tag. For it to work as intended, you have to place the executable in the root directory of Taglib.<br>
    
    If you modified the source code, you can compile it with the command:<br>
    `zig build-exe -fstrip -O ReleaseFast -target x86_64-<windows/linux/macos> --name <W/L/M>_tag_dereferencer -femit-bin=tag_dereferencer/tag_dereferencerexe tag_dereferencer/tag_dereferencer.zig`<br>
    (assuming your cwd is the Taglib folder and kept the folderstucture intakt)