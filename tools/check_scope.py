import re, sys
src=open('lisp/SPA.LSP').read()
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
