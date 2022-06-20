# Vala-Indenter

This is my playground for implementing a new indenter for Vala.

After I'm satisified, I will rewrite it in C and upstream it to GtkSourceView.

# Features
- Automatically continue one-line comments (`//`)
- Automatically continue multi-line comments (`/* */`)
- Indent multiline method calls / definitons:

```
foo.bar.baz (a,
             b,
             c,
             d);
```
- Indent and unindent after one-line for/while/if-Blocks:
```
if (foo)
    code (); // Automatically land here
// And then here
```
- Automatically indent after `{`
- Go back after a broken up line
```
foo ("aaaaaaaaalonnggggggstringgggggg",
     foo);
// Automatically land here
```

