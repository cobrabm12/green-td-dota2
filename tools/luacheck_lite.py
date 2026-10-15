"""Very small Lua sanity checker (no Lua needed): balanced blocks, brackets and strings.
Usage: python -I tools/luacheck_lite.py <dir-or-file> ..."""
import os, re, sys

KEYWORDS = {'function', 'if', 'for', 'while', 'do', 'repeat', 'end', 'until', 'then', 'elseif', 'else', 'local',
            'return', 'break', 'in', 'and', 'or', 'not', 'nil', 'true', 'false', 'goto'}


def tokens(src):
    i, n, line = 0, len(src), 1
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1; i += 1; continue
        if c.isspace():
            i += 1; continue
        if src.startswith('--', i):
            m = re.match(r'--\[(=*)\[', src[i:])
            if m:
                close = ']' + m.group(1) + ']'
                j = src.find(close, i)
                if j < 0:
                    raise SyntaxError('unclosed long comment at line %d' % line)
                line += src.count('\n', i, j); i = j + len(close); continue
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        m = re.match(r'\[(=*)\[', src[i:])
        if m:
            close = ']' + m.group(1) + ']'
            j = src.find(close, i)
            if j < 0:
                raise SyntaxError('unclosed long string at line %d' % line)
            line += src.count('\n', i, j); i = j + len(close)
            yield ('str', '', line); continue
        if c in '"\'':
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == '\\':
                    j += 1
                if src[j] == '\n':
                    raise SyntaxError('newline in string at line %d' % line)
                j += 1
            if j >= n:
                raise SyntaxError('unclosed string at line %d' % line)
            i = j + 1
            yield ('str', '', line); continue
        m = re.match(r'[A-Za-z_]\w*', src[i:])
        if m:
            w = m.group(0); i += len(w)
            yield ('kw' if w in KEYWORDS else 'name', w, line); continue
        m = re.match(r'0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+', src[i:])
        if m:
            i += len(m.group(0)); yield ('num', m.group(0), line); continue
        m = re.match(r'\.\.\.|\.\.|==|~=|<=|>=|::|[-+*/%^#<>=(){}\[\];:,.]', src[i:])
        if m:
            i += len(m.group(0)); yield ('op', m.group(0), line); continue
        raise SyntaxError('unexpected character %r at line %d' % (c, line))


def check(path):
    src = open(path, encoding='utf-8').read()
    stack = []
    expect_do = 0
    prev = None
    for kind, val, line in tokens(src):
        if kind == 'kw':
            if val in ('function', 'if', 'repeat'):
                stack.append((val, line))
            elif val in ('for', 'while'):
                stack.append((val, line)); expect_do += 1
            elif val == 'do':
                if expect_do:
                    expect_do -= 1
                else:
                    stack.append(('do', line))
            elif val == 'end':
                if not stack or stack[-1][0] == 'repeat':
                    raise SyntaxError('unexpected end at line %d' % line)
                stack.pop()
            elif val == 'until':
                if not stack or stack[-1][0] != 'repeat':
                    raise SyntaxError('unexpected until at line %d' % line)
                stack.pop()
            elif val in ('then', 'elseif', 'else') and (not stack or stack[-1][0] != 'if'):
                raise SyntaxError('%s outside if at line %d' % (val, line))
        elif kind == 'op':
            if val in '({[':
                stack.append((val, line))
            elif val in ')}]':
                want = {')': '(', '}': '{', ']': '['}[val]
                if not stack or stack[-1][0] != want:
                    raise SyntaxError('unbalanced %s at line %d (open: %s)' % (val, line, stack[-1] if stack else None))
                stack.pop()
            elif val == '=' and prev and prev[0] == 'op' and prev[1] in ('=', '<', '>', '~'):
                raise SyntaxError('odd operator at line %d' % line)
        if kind == 'name' and val in ('elif', 'elsif', 'endif', 'fi', 'then_'):
            raise SyntaxError('suspicious word %s at line %d' % (val, line))
        if kind == 'op' and val == '!=':
            raise SyntaxError('!= at line %d' % line)
        prev = (kind, val)
    if stack:
        raise SyntaxError('unclosed %s opened at line %d' % stack[-1])


def main():
    bad = 0
    files = []
    for p in sys.argv[1:]:
        if os.path.isdir(p):
            for root, _, names in os.walk(p):
                files += [os.path.join(root, n) for n in names if n.endswith('.lua')]
        else:
            files.append(p)
    for f in sorted(files):
        try:
            check(f)
        except SyntaxError as e:
            bad += 1
            print('FAIL %s: %s' % (f, e))
    print('%d files checked, %d with problems' % (len(files), bad))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
