import re, sys, collections
src = open('lisp/SPA.LSP').read()

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
setqglob = set(re.findall(r'\(setq\s+(spa:\*[^\s()]+)', clean))
called = set(re.findall(r'\(([a-zA-Z][\w:>+*/=<-]*)', clean))
used_glob = set(re.findall(r'(spa:\*[\w*-]+)', clean))
missing = sorted(x for x in called if x.startswith(('spa:','rc:')) and x not in defined)
print("undefined fns:", missing)
print("undefined globals:", sorted(g for g in used_glob if g not in setqglob))
# unused defuns
print("defined but never called:", sorted(d for d in defined if d not in called))
