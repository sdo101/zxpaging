# makes the "source level debugging" file that the DeZog debugger in VS Code reads, build\<project>.sld, so that the
# program can be stepped through in the emulator with the source on screen: which address, in which page, is which line
#
# sjasmplus would normally write this file, but here it only stitches finished binaries into the nex file, it is
# Boriel's own assembler that turns each module into machine code, and that one writes nothing of the kind, so:
#   - each module's assembly, build\<module>.asm, as the compiler wrote it, is copied with a label put in front of
#     every line, and assembled again by Boriel's assembler with a map of the labels asked for
#   - the binary that makes is compared with build\<module>.bin, and the module is left out if they differ, so an
#     address in the file is always an address in the program
#   - the map then gives the address of every line, and the nex layout, src\sjasmplus.cfg, gives each module's page
# what a line of machine code is shown as:
#   - code compiled from BASIC is shown in build\<module>.asm, where the names of the routines and variables are
#   - code written in an Asm block is shown where it was written, in the .bas file itself (the compiler marks where
#     each block came from with a #line, the lines are counted on from there and checked against the file's text)
#
# usage: python tools\make-sld.py <project name> [--jobs N]      run from the project folder, after a build

import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.getcwd()
BUILD = 'build'
SOURCE = 'src'


def find_assembler():
    # Boriel's assembler is in the root folder that holds the tools, found as build.ps1 finds it: the nearest folder
    # above the project's that has boriel\zxbc.py in it
    folder = ROOT
    while True:
        if os.path.isfile(os.path.join(folder, 'boriel', 'zxbc.py')):
            return os.path.join(folder, 'boriel', 'zxbasm.py')
        parent = os.path.dirname(folder)
        if parent == folder:
            sys.exit('no folder above %s has boriel\\zxbc.py in it' % ROOT)
        folder = parent


ASSEMBLER = find_assembler()
PAGE_SIZE = 8192
DATA_WORDS = {'defb', 'defw', 'defm', 'defs', 'db', 'dw', 'dm', 'ds', 'incbin'}


def read_lines(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        return f.read().split('\n')


def modules_and_pages():
    # the core is two pages from $8000, the ones the nex layout puts in MMU 4 and 5, the loader is the page it puts in
    # MMU 6, at $C000, and every stage and library is one page at $6000, its page number is on its line of the layout
    layout = read_lines(os.path.join(SOURCE, 'sjasmplus.cfg'))
    slot = {}
    for line in layout:
        m = re.match(r'\s*MMU\s+([456])\s*,\s*(\d+)', line, re.I)
        if m:
            slot.setdefault(int(m.group(1)), int(m.group(2)))
    if len(slot) < 3:
        sys.exit('%s does not say which pages are in MMU 4, 5 and 6' % os.path.join(SOURCE, 'sjasmplus.cfg'))
    found = [{'name': 'core', 'org': 0x8000, 'pages': [slot[4], slot[5]]}, {'name': 'load', 'org': 0xC000, 'pages': [slot[6]]}]
    for line in layout:
        m = re.search(r'PAGE\s+(\d+)\s*:.*INCBIN\s+"(stage-[^"]+)\.bin"', line, re.I)
        if m:
            found.append({'name': m.group(2), 'org': 0x6000, 'pages': [int(m.group(1))]})
    return found


def tidy(text):
    # a line of assembly with its comment and its spacing taken away, for comparing two lines
    return re.sub(r'\s+', ' ', text.split(';')[0]).strip().lower()


def label_name(raw):
    # ._s_core_message is s_core_message, .core.__MAIN_PROGRAM__ is core.__MAIN_PROGRAM__
    name = raw.lstrip('.')
    if name.startswith('_') and not name.startswith('__'):
        name = name[1:]
    return re.sub(r'[^\w.]', '_', name)


def make_part(module):
    name = module['name']
    asm_path = os.path.join(BUILD, name + '.asm')
    bin_path = os.path.join(BUILD, name + '.bin')
    map_path = os.path.join(BUILD, name + '.map')
    part_path = os.path.join(BUILD, name + '.sld-part')
    work = os.path.join(BUILD, 'sld')
    newest = max(os.path.getmtime(p) for p in (asm_path, bin_path, map_path, __file__, os.path.join(SOURCE, 'sjasmplus.cfg')))
    if os.path.exists(part_path) and os.path.getmtime(part_path) > newest:
        return name, 'kept', read_lines(part_path)

    asm = read_lines(asm_path)
    marked = []
    for index, line in enumerate(asm):
        text = line.strip()
        # N.B: not in front of an org, a label there is at the address before it, and the binary would start from that
        if text and not text.startswith('#') and text.split()[0].lower() != 'org':
            marked.append('__sld_%d:' % index)
        marked.append(line)
    marked_path = os.path.join(work, name + '.asm')
    with open(marked_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(marked))
    out_bin = os.path.join(work, name + '.bin')
    out_map = os.path.join(work, name + '.map')
    done = subprocess.run([sys.executable, ASSEMBLER, marked_path, '-N', '-o', out_bin, '-M', out_map],
                          capture_output=True, text=True)
    if done.returncode != 0 or not os.path.exists(out_bin):
        return name, 'NOT DONE, the assembler said: ' + (done.stderr or done.stdout).strip()[:300], []
    with open(out_bin, 'rb') as f:
        made = f.read()
    with open(bin_path, 'rb') as f:
        built = f.read()
    # N.B: build.ps1 pads core.bin to its two full pages, the code is what comes first
    if made != built[:len(made)] or (name != 'core' and len(made) != len(built)):
        return name, 'NOT DONE, assembling it again did not give the same binary', []

    address = {}
    for line in read_lines(out_map):
        m = re.match(r'([0-9A-Fa-f]{4}):\s+\S*__sld_(\d+)\s*$', line)
        if m:
            address[int(m.group(2))] = int(m.group(1), 16)
    order = sorted(address)
    end = module['org'] + len(made)
    size = {}
    for at, index in enumerate(order):
        after = address[order[at + 1]] if at + 1 < len(order) else end
        size[index] = after - address[index]

    def page_of(addr):
        return module['pages'][min((addr - module['org']) // PAGE_SIZE, len(module['pages']) - 1)]

    def is_code(index):
        words = asm[index].split()
        return size.get(index, 0) > 0 and words and words[0].lower() not in DATA_WORDS

    # where each line is shown: its own line of the module's assembly, unless it is in an Asm block
    asm_file = BUILD + '/' + name + '.asm'
    shown = {index: (asm_file, index + 1) for index in order if is_code(index)}
    markers = [i for i, line in enumerate(asm) if line.startswith('#line')]
    sources = {}
    for at, marker in enumerate(markers):
        m = re.match(r'#line\s+(\d+)\s+"([^"]+)"', asm[marker])
        if not m:
            continue
        first, file_name = int(m.group(1)), m.group(2)
        last = markers[at + 1] if at + 1 < len(markers) else len(asm)
        block = [i for i in range(marker + 1, last) if i in shown]
        if not block:
            continue
        if file_name not in sources:
            sources[file_name] = read_lines(file_name) if os.path.exists(file_name) else None
        source = sources[file_name]
        if source is None:
            continue
        # the compiler's count is not always from the line one would expect, so the text decides: the offset at
        # which most lines of the block are, word for word, the lines of the file
        best, best_hits = 0, -1
        for offset in (-1, 0, -2, 1):
            hits = 0
            for i in block:
                n = first + (i - marker - 1) + offset
                if 1 <= n <= len(source) and tidy(source[n - 1]) == tidy(asm[i]):
                    hits += 1
            if hits > best_hits:
                best, best_hits = offset, hits
        if best_hits * 2 < len(block):
            continue
        shown_file = file_name.replace('\\', '/')
        if os.path.isabs(file_name):
            shown_file = os.path.abspath(file_name).replace('\\', '/')
        for i in block:
            shown[i] = (shown_file, first + (i - marker - 1) + best)

    # the labels: the routines and the places within them, by the names the compiler gave them
    where = {}
    for index, line in enumerate(asm):
        m = re.match(r'([.\w]+):', line)
        if m:
            where.setdefault(m.group(1).lstrip('.'), index + 1)
    prefix = name.replace('-', '_')
    lines, seen = [], set()
    for line in read_lines(map_path):
        m = re.match(r'([0-9A-Fa-f]{4}):\s+(\S+)\s*$', line)
        if not m:
            continue
        addr, raw = int(m.group(1), 16), m.group(2)
        label = label_name(raw)
        if not (module['org'] <= addr < end) or label in seen:
            continue
        seen.add(label)
        lines.append('%s|%d||0|%d|%d|L|%s,%s,,' % (asm_file, where.get(raw.lstrip('.'), 1), page_of(addr), addr, prefix, label))
    for index in sorted(shown):
        file_name, number = shown[index]
        lines.append('%s|%d||0|%d|%d|T|' % (file_name, number, page_of(address[index]), address[index]))
    with open(part_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))
    in_bas = sum(1 for index in shown if shown[index][0] != asm_file)
    return name, '%d instructions, %d of them shown in the .bas' % (len(shown), in_bas), lines


def main():
    project = sys.argv[1]
    jobs = int(sys.argv[sys.argv.index('--jobs') + 1]) if '--jobs' in sys.argv else (os.cpu_count() or 2)
    os.makedirs(os.path.join(BUILD, 'sld'), exist_ok=True)
    modules = modules_and_pages()
    out = ['|SLD.data.version|1',
           '||K|KEYWORDS|WPMEM,LOGPOINT,ASSERTION',
           SOURCE + '/sjasmplus.cfg|1||0|-1|-1|Z|pages.size:8192,pages.count:224,slots.count:8,'
           'slots.adr:0,8192,16384,24576,32768,40960,49152,57344']
    failed = 0
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        for name, said, lines in pool.map(make_part, modules):
            if not lines:
                failed += 1
            if said != 'kept':
                print('    %-32s %s' % (name, said))
            out.extend(line for line in lines if line)
    sld = os.path.join(BUILD, project + '.sld')
    with open(sld, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(out) + '\n')
    print('    %s: %d modules, %d lines%s' % (sld, len(modules) - failed, len(out), ', %d modules NOT DONE' % failed if failed else ''))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
