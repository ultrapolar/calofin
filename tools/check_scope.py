import re, sys
import sys
files=sys.argv[1:] or ['lisp/spa/SPA.LSP']
src='\n'.join(open(f).read() for f in files)
# strip strings+comments
out=[];i=0;instr=False
while i<len(src):
    ch=src[i]
    if instr:
        if ch=='\\': out.append('  ');i+=2;continue
        if ch=='"': instr=False
        out.append(' ' if ch!='\n' else '\n');i+=1;continue
    if ch=='"': instr=True;out.append(' ');i+=1;continue
    if ch==';':
        while i<len(src) and src[i]!='\n': out.append(' ');i+=1
        continue
    out.append(ch);i+=1
clean=''.join(out)

# split into top-level forms
forms=[];depth=0;start=None
for i,ch in enumerate(clean):
    if ch=='(':
        if depth==0: start=i
        depth+=1
    elif ch==')':
        depth-=1
        if depth==0: forms.append((start,clean[start:i+1]))

globals_declared=set(re.findall(r'\(setq\s+(spa:\*[\w*-]+)', clean))

problems=[]
for pos,f in forms:
    m=re.match(r'\(defun\s+([^\s()]+)\s*\(([^)]*)\)', f, re.S)
    if not m: continue
    name=m.group(1); arglist=m.group(2)
    toks=arglist.replace('/',' / ').split()
    if '/' in toks:
        k=toks.index('/'); params=toks[:k]; locals_=toks[k+1:]
    else:
        params=toks; locals_=[]
    declared=set(params)|set(locals_)
    body=f[m.end():]
    line=clean[:pos].count('\n')+1
    # foreach vars
    for fv in re.findall(r'\(foreach\s+([^\s()]+)', body):
        if fv not in declared:
            problems.append((line,name,'foreach',fv))
    # setq targets
    for sq in re.finditer(r'\(setq\s+((?:[^()]|\([^()]*\))*)', body):
        seg=sq.group(1)
        # crude: take tokens at even positions that are bare symbols
        toks2=re.findall(r'^\s*([A-Za-z][\w:*+/<>=-]*)|\)\s*([A-Za-z][\w:*+/<>=-]*)', seg)
        for a,b in toks2:
            v=a or b
            if not v: continue
            if v.startswith('spa:*'):
                if v not in globals_declared: problems.append((line,name,'setq-global',v))
                continue
            if v not in declared and not v.startswith('spa:') and v not in ('nil','t'):
                problems.append((line,name,'setq',v))
for p in sorted(set(problems)):
    print(f"line {p[0]:5d}  {p[1]:22s} {p[2]:12s} {p[3]}")

# ---- case-collision check --------------------------------------------------
# AutoLISP symbols are case-insensitive: sP IS sp, Bx IS bx.  Declaring or
# using two spellings that fold to the same name inside one defun means one
# variable silently doing two jobs - the bug class that broke NORMIESTEP's
# side lines (sP clobbered sp) and ABCDEF's corners (Bx clobbered bx).
SYM = re.compile(r"[A-Za-z_:*][\w:*+/<>=!?-]*")
for pos, f in forms:
    m = re.match(r"\(defun\s+([^\s()]+)\s*\(([^)]*)\)", f, re.S)
    if not m:
        continue
    name = m.group(1)
    arglist = m.group(2)
    line = clean[:pos].count("\n") + 1
    toks = arglist.replace("/", " ").split()
    # duplicate declarations after case-folding (covers bx + Bx)
    folded = {}
    for v in toks:
        lv = v.lower()
        if lv in folded and v != "/":
            print(f"line {line:5d}  {name:22s} case-dup     "
                  f"{folded[lv]} / {v} declared in one arglist")
        folded.setdefault(lv, v)
    # a body spelling that folds onto a declared local (covers sp + sP)
    body = f[m.end():]
    spellings = {}
    for t in SYM.findall(body):
        spellings.setdefault(t.lower(), set()).add(t)
    for lv, first in folded.items():
        others = spellings.get(lv, set()) - {first}
        if others and lv not in ("t", "nil", "pi"):
            print(f"line {line:5d}  {name:22s} case-mix     "
                  f"local {first} also written as "
                  f"{', '.join(sorted(others))}")
