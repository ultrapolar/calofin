import re, sys, collections
import sys
files = sys.argv[1:] or ['lisp/spa/SPA.LSP']
src = '\n'.join(open(f).read() for f in files)

# tokenize: strip ; comments (outside strings) and track strings
i=0; depth=0; line=1; instr=False; out=[]
starts=[]
clean=[]
while i < len(src):
    ch = src[i]
    if ch == '\n':
        line += 1; clean.append(ch); i+=1; continue
    if instr:
        if ch == '\\':
            clean.append(' '); clean.append(' '); i+=2; continue
        if ch == '"':
            instr=False
        clean.append(' '); i+=1; continue
    if ch == '"':
        instr=True; clean.append(' '); i+=1; continue
    if ch == ';':
        while i < len(src) and src[i] != '\n':
            clean.append(' '); i+=1
        continue
    if ch == '(':
        depth+=1; starts.append(line)
    elif ch == ')':
        depth-=1
        if depth < 0:
            print("EXTRA ) at line", line); sys.exit(1)
        starts.pop()
    clean.append(ch); i+=1
if instr: print("UNTERMINATED STRING")
print("final depth:", depth)
if depth: print("unclosed opened at lines:", starts[:10])

clean=''.join(clean)
defined = set(re.findall(r'\(defun\s+([^\s()]+)', clean))
# prefixes from the file rather than a hardcoded one (STANDARDS 7.5)
prefixes = sorted(set(re.findall(r'\(defun\s+([a-zA-Z][\w-]*):', clean)))
setqglob = set(re.findall(r'\(setq\s+([a-zA-Z][\w-]*:\*[^\s()]+)', clean))
called = set(re.findall(r'\(([a-zA-Z][\w:>+*/=<-]*)', clean))
used_glob = set(re.findall(r'([a-zA-Z][\w-]*:\*[\w*-]+)', clean))
missing = sorted(x for x in called
                 if any(x.startswith(pre + ':') for pre in prefixes)
                 and x not in defined)
print("undefined fns:", missing)
print("undefined globals:", sorted(g for g in used_glob if g not in setqglob))
# unused defuns
print("defined but never called:", sorted(d for d in defined if d not in called))


# --- special-form arity -------------------------------------------------
#
# (if a b c d) is accepted by every parser and dies at the AutoCAD
# command line, and the usual way to write one is to break a long string
# over two lines and forget the strcat holding it together.  The same
# goes for a (setq ...) left with an odd number of arguments.  Both need
# the form's real shape, so this reads the file properly rather than
# regexing it -- with string literals standing as one token each, since
# blanking them would hide the very arguments being counted.
def forms(text):
    """The file as nested lists; a string literal is the token '"'."""
    i, n = 0, len(text)
    stack, top = [], []
    cur = top
    while i < n:
        ch = text[i]
        if ch == '"':                      # a blanked-out literal marker
            cur.append('"'); i += 1; continue
        if ch == '(':
            new = []
            cur.append(new); stack.append(cur); cur = new; i += 1; continue
        if ch == ')':
            if stack:
                cur = stack.pop()
            i += 1; continue
        if ch in " \t\r\n'":
            i += 1; continue
        j = i
        while j < n and text[j] not in " \t\r\n()'\"":
            j += 1
        cur.append(text[i:j]); i = max(j, i + 1)
    return top


def walk(form, bad):
    if not isinstance(form, list):
        return
    head = form[0] if form and isinstance(form[0], str) else None
    if head == 'if' and not (3 <= len(form) <= 4):
        bad.append(f"(if ...) takes 2 or 3 arguments, got {len(form) - 1}")
    if head == 'setq' and (len(form) - 1) % 2:
        bad.append(f"(setq ...) takes pairs, got {len(form) - 1} arguments")
    for sub in form:
        walk(sub, bad)


# put a one-character stand-in back where each string literal was
lit = []
i = 0; instr = False
while i < len(src):
    ch = src[i]
    if instr:
        if ch == '\\':
            i += 2; continue
        if ch == '"':
            instr = False; lit.append('"')
        i += 1; continue
    if ch == '"':
        instr = True; i += 1; continue
    if ch == ';':
        while i < len(src) and src[i] != '\n':
            i += 1
        continue
    lit.append(ch); i += 1

bad = []
for f in forms(''.join(lit)):
    walk(f, bad)
print("bad form arity:", bad)
if bad:
    sys.exit(1)
