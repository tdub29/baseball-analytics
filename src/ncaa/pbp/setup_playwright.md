# Playwright + Chromium setup (NCAA PBP scraping)

The fetch scripts use Playwright with Chromium to load stats.ncaa.org (avoids Access Denied from direct HTTP).

## Option A: After Visual Studio Build Tools are installed

If you installed **Microsoft C++ Build Tools** (or full Visual Studio), in a new terminal run:

```powershell
pip install playwright
playwright install chromium
```

## Option B: Conda (no C++ build tools needed)

From the `battles` folder:

```powershell
conda install -c conda-forge playwright -y
playwright install chromium
```

## Option C: Use a Python that has greenlet wheels

If you have Python 3.10 or 3.11, they often have pre-built `greenlet` wheels on Windows, so:

```powershell
py -3.11 -m pip install playwright
py -3.11 -m playwright install chromium
```

Then run fetch scripts with that Python, e.g. `py -3.11 fetch_multiple_ncaa_pbp.py 6500243`.

## Verify

```powershell
python -c "from playwright.sync_api import sync_playwright; p=sync_playwright().start(); b=p.chromium.launch(); b.close(); p.stop(); print('Playwright + Chromium OK')"
```

If that prints `Playwright + Chromium OK`, you can run:

```powershell
python fetch_multiple_ncaa_pbp.py 6500243
```
