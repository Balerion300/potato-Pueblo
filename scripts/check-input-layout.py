"""Test the delivered application, preserving default geometry until recorded."""
import os, pathlib, platform, subprocess, sys, tempfile, urllib.request, zipfile
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tests'))
from fixture_server import Fixture
root=pathlib.Path(__file__).resolve().parents[1]
archive=pathlib.Path(sys.argv[1])
out=root/'artifacts/input-layout'
out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='potato-input-layout-') as tmp:
    folder=pathlib.Path(tmp)
    if platform.system()=='Darwin':
        subprocess.run(['ditto','-x','-k',str(archive.resolve()),str(folder)],check=True)
    else:
        with zipfile.ZipFile(archive) as z:z.extractall(folder)
    resources=next(folder.rglob('BUILD.json')).parent
    exe=resources.parent/'MacOS/PotatoPueblo' if platform.system()=='Darwin' else resources/'runtime/bin/wish86s.exe'
    for scenario in ['fresh','collapsed']:
        with Fixture() as fixture:
            label=archive.parent.name+'-'+scenario
            receipt=out/(label+'.txt')
            receipt.write_text('')
            env=dict(os.environ,**fixture.environment(),POTATO_HOME=str(folder/scenario),
                     POTATO_TEST_SOURCE_ROOT=str(resources),POTATO_TEST_RESULT=str(receipt),
                     POTATO_LAYOUT_LABEL=label)
            if scenario=='collapsed':env['POTATO_COLLAPSED_INPUT']='1'
            if platform.system()!='Darwin':
                env.update(TCL_LIBRARY=str(resources/'runtime/lib/tcl8.6'),TK_LIBRARY=str(resources/'runtime/lib/tk8.6'))
            subprocess.run([str(exe),str(root/'tests/run.tcl'),str(root/'tests/input-layout.tcl')],env=env,check=True,timeout=45)
            print(receipt.read_text(),flush=True)
