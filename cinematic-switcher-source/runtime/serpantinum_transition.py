from transition_guard import enter
enter('serpantinum')

import sys, time, math, subprocess, shutil, argparse
import ctypes
import os
import tempfile

from shiboken6 import getCppPointer
from pathlib import Path
import numpy as np
from PySide6.QtCore import Qt, QTimer, QRect, QRectF, QPointF
from PySide6.QtGui import (
    QCursor, QGuiApplication, QPainter, QColor, QPen, QFont,
    QPixmap, QRasterWindow, QRadialGradient, QSurfaceFormat,
)

BASE = Path.home()/'.local/share/desktop-switcher'
MAIN = (BASE / "main-output").read_text().strip()
WALLPAPER_STATE = Path.home() / ".cache/serpantinum/wallpaper"
VIDEO_EXTENSIONS = {".mp4", ".mkv", ".mov", ".webm"}
IMPACT_AT = 4.65
SETTLE_DURATION = .85
HANDOFF_DURATION = .15
parser=argparse.ArgumentParser()
parser.add_argument('--switch', action='store_true')
parser.add_argument('--wallpaper', type=Path)
parser.add_argument('--logo', type=Path)
args=parser.parse_args()
original_qt_environment = {
    key: os.environ[key] for key in ("QT_QPA_PLATFORM", "QT_WAYLAND_SHELL_INTEGRATION")
    if key in os.environ
}
os.environ["QT_QPA_PLATFORM"] = "wayland"
os.environ["QT_WAYLAND_SHELL_INTEGRATION"] = "layer-shell"
app = QGuiApplication([sys.argv[0]])
layer_bridge = ctypes.CDLL(str(BASE / "serpantinum_layer.so"))
layer_bridge.configure_cinematic.argtypes = (ctypes.c_void_p, ctypes.c_void_p)
layer_bridge.configure_cinematic.restype = None
rng=np.random.default_rng(2026)
N=720
a=rng.uniform(0,math.tau,N); r=rng.uniform(.4,2.4,N); z=rng.uniform(.2,1,N); delay=rng.uniform(0,.7,N)
def ease(x):
    x=np.clip(x,0,1); return x*x*(3-2*x)
def ink(alpha, rgb=(44,245,191)):
    return QColor(*rgb,int(np.clip(alpha,0,255)))
def capture(screen):
    pix=QPixmap()
    try:
        result=subprocess.run(['grim','-o',screen.name(),'-'],capture_output=True,timeout=3)
        if result.returncode==0: pix.loadFromData(result.stdout)
    except (OSError,subprocess.TimeoutExpired): pass
    return pix
logo=QPixmap(str(args.logo)) if args.logo else QPixmap()
# Sample the supplied transparent logo; otherwise use an original S-shaped emblem.
if not logo.isNull():
    im=logo.toImage().scaled(160,160,Qt.AspectRatioMode.KeepAspectRatio)
    pts=[((x-im.width()/2)/160,(y-im.height()/2)/160) for y in range(im.height()) for x in range(im.width()) if im.pixelColor(x,y).alpha()>128 and max(im.pixelColor(x,y).red(),im.pixelColor(x,y).green(),im.pixelColor(x,y).blue())>70]
else: pts=[]
if pts:
    target=np.array(pts)[rng.integers(0,len(pts),N)]
else:
    u=rng.uniform(0,1,N); target=np.column_stack((.29*np.sin(u*math.tau)+rng.normal(0,.018,N), (u-.5)*.85))
start=0; process=None; log=None; windows=[]; reveal=None; failed=False
wallpaper_images = {}


def selected_wallpaper(output):
    # WallpaperEngine.qml restores this same per-output state file.
    saved_path = (WALLPAPER_STATE / f"current_{output}").read_text().strip()
    if not saved_path:
        raise ValueError(f"No wallpaper selected for {output}")
    return Path(saved_path).resolve(strict=True)


def wallpaper_pixmap(path):
    if path not in wallpaper_images:
        image = QPixmap()
        if not image.load(str(path)) or image.isNull():
            raise ValueError(f"QPixmap could not load {path}")
        wallpaper_images[path] = image
    return wallpaper_images[path]


def video_wallpaper_frame(path):
    # Use the selected monitor's video directly. The stock shell's shared
    # preview cache can be overwritten when both monitors restore together.
    result = subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error", "-i", str(path), "-frames:v", "1",
         "-f", "image2pipe", "-c:v", "png", "-"],
        capture_output=True, timeout=3,
    )
    image = QPixmap()
    if result.returncode != 0 or not image.loadFromData(result.stdout):
        raise ValueError(f"Could not extract a wallpaper frame from {path}")
    return image


def load_wallpapers():
    images = []
    for window in windows:
        try:
            source = Path((frame_dir / f"source-{window.output}").read_text().rstrip("\n"))
            if source.suffix.lower() in VIDEO_EXTENSIONS:
                image = video_wallpaper_frame(source)
            else:
                image = wallpaper_pixmap(source.resolve(strict=True))
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            print(f"{window.output}: {error}", file=log, flush=True)
            (frame_dir / "wallpaper-error").touch()
            return
        images.append((window, source, image))
    for window, source, image in images:
        window.wall = image
        print(f"{window.output}: loaded {source} ({image.width()}x{image.height()})", file=log, flush=True)
    (frame_dir / "wallpaper-loaded").touch()


def draw_wallpaper(painter, rect, pixmap, zoom):
    # Match the desktop's centered Image.PreserveAspectCrop on every output.
    w, h = rect.width(), rect.height()
    scale = max(w / pixmap.width(), h / pixmap.height()) * zoom
    ww, hh = pixmap.width() * scale, pixmap.height() * scale
    painter.drawPixmap(QRectF((w - ww) / 2, (h - hh) / 2, ww, hh), pixmap, QRectF(pixmap.rect()))


def impact_zoom(progress):
    # The same quartic ease-out as the Windows wallpaper impact.
    return 1 + .12 * (1 - progress) ** 4


def blend_live_desktop(painter, rect, elapsed):
    # Keep the impact opaque. Blend in the windows only as the zoom settles.
    handoff_start = SETTLE_DURATION - HANDOFF_DURATION
    if elapsed <= handoff_start:
        return
    progress = (elapsed - handoff_start) / HANDOFF_DURATION
    alpha = round(255 * (1 - float(ease(progress))))
    painter.setCompositionMode(QPainter.CompositionMode.CompositionMode_DestinationIn)
    painter.fillRect(rect, QColor(0, 0, 0, alpha))


class Panel(QRasterWindow):
    def __init__(self, screen, shot):
        super().__init__()
        self.setScreen(screen)
        self.output = screen.name()
        self.shot = shot
        self.main = self.output == MAIN
        self.wall = wallpaper_pixmap(args.wallpaper) if args.wallpaper and not args.switch else QPixmap()
        surface_format = QSurfaceFormat()
        surface_format.setAlphaBufferSize(8)
        self.setFormat(surface_format)
        self.setTitle('Cinematic Desktop Transition')
        self.resize(screen.size())
        self.setCursor(QCursor(Qt.CursorShape.BlankCursor))
        layer_bridge.configure_cinematic(getCppPointer(self)[0], getCppPointer(screen)[0])

    def paintEvent(self,event):
        p=QPainter(self); p.setRenderHint(QPainter.RenderHint.Antialiasing); p.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)
        w,h=self.width(),self.height(); cx,cy=w/2,h/2; s=min(w,h)*.32; t=min(time.monotonic()-start, IMPACT_AT)
        rect = QRect(0, 0, w, h)
        if reveal is not None:
            elapsed = time.monotonic() - reveal
            progress = min(1.0, elapsed / SETTLE_DURATION)
            p.fillRect(rect, QColor("#0a0a0f") if not failed else Qt.GlobalColor.black)
            if failed or self.wall.isNull():
                # A failed transaction returns to the outgoing screenshot while rollback completes.
                if not self.shot.isNull():
                    p.setOpacity(float(ease(progress)))
                    draw_wallpaper(p, rect, self.shot, 1)
            else:
                draw_wallpaper(p, rect, self.wall, impact_zoom(progress))
                if args.switch:
                    blend_live_desktop(p, rect, elapsed)
            return
        p.fillRect(rect,QColor(0,0,0))
        if t<.65:
            p.setOpacity(1-float(ease(t/.65))); p.drawPixmap(rect,self.shot); return
        if not self.main: return
        intro=float(ease((t-.65)/.9)); f=ease((t-1.6-delay)/2.0); energy=float(ease((t-1)/1.5)); pulse=.75+.25*math.sin(t*3)
        glow=QRadialGradient(cx,cy,s*2.6); glow.setColorAt(0,ink(65*intro*energy)); glow.setColorAt(.4,ink(16*intro)); glow.setColorAt(1,ink(0)); p.fillRect(rect,glow)
        # Tilted, counter-rotating orbital rings with luminous segmented arcs.
        for j in range(4):
            p.save(); p.translate(cx,cy); p.rotate(j*43+t*(18 if j%2 else -18)); p.scale(1,.48+j*.12)
            rr=s*(.65+j*.17); rect=QRectF(-rr,-rr,2*rr,2*rr)
            for k in range(3):
                p.setPen(QPen(ink(120*intro*energy*pulse),1.5+j*.35)); p.drawArc(rect,int((k*120+t*45)*16),int(74*16))
            p.restore()
        ang=a+t*(.4+z*.5); rad=r*s*1.6/(1+.24*t*z)
        x=cx+np.cos(ang)*rad*(1-f)+target[:,0]*s*f; y=cy+np.sin(ang)*rad*.65*(1-f)+target[:,1]*s*f
        p.setFont(QFont('monospace',9))
        for i in range(N):
            alpha=(85+150*z[i])*intro*float(ease((t-.65-delay[i])/.6))*(1-.65*float(ease((t-3.5)/.7)))
            if i%7==0 and f[i]<.55:
                p.setPen(ink(alpha)); p.drawText(QPointF(x[i],y[i]),'01ABCDEF'[i%8])
            else:
                p.setPen(Qt.PenStyle.NoPen); p.setBrush(ink(alpha*.15)); p.drawEllipse(QPointF(x[i],y[i]),4*z[i],4*z[i]); p.setBrush(ink(alpha)); p.drawEllipse(QPointF(x[i],y[i]),1.8*z[i],1.8*z[i])
        solid=float(ease((t-3.1)/.9))
        if not logo.isNull():
            k=s/max(logo.width(),logo.height()); ww,hh=logo.width()*k,logo.height()*k; p.setOpacity(solid); p.drawPixmap(QRectF(cx-ww/2,cy-hh/2,ww,hh),logo,QRectF(logo.rect())); p.setOpacity(1)
        else:
            p.setPen(QPen(ink(240*solid),4)); path=[QPointF(cx+.29*math.sin(u*math.tau)*s,cy+(u-.5)*.85*s) for u in np.linspace(0,1,100)]
            for l,b in zip(path,path[1:]): p.drawLine(l,b)
        p.setPen(ink(230*solid)); font=QFont('sans-serif',15); font.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing,5); p.setFont(font); p.drawText(QRectF(0,cy+s*.83,w,50),Qt.AlignmentFlag.AlignCenter,'SERPANTINUM')
    def keyPressEvent(self,event):
        if event.key()==Qt.Key.Key_Escape and process is None: app.quit()

def sound():
    if shutil.which('mpv') and (BASE/'serpantinum.wav').exists():
        subprocess.Popen(['mpv','--no-video','--really-quiet','--volume=45',str(BASE/'serpantinum.wav')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
def tick():
    global process,log,reveal,failed
    t=time.monotonic()-start
    if args.switch and process is None and t>=1.8:
        log_path = BASE / "serpantinum-switch.log"
        log_path.write_text("")
        log = log_path.open("a", buffering=1)
        environment = dict(os.environ, SERPANTINUM_CINEMATIC_DIR=str(frame_dir))
        # Layer-shell integration belongs to this renderer, not its child services.
        for key in ("QT_QPA_PLATFORM", "QT_WAYLAND_SHELL_INTEGRATION"):
            if key in original_qt_environment:
                environment[key] = original_qt_environment[key]
            else:
                environment.pop(key, None)
        process=subprocess.Popen(['bash',str(BASE/'switch.sh'),'serpantinum'],stdout=log,stderr=subprocess.STDOUT,env=environment)
    if process is not None and reveal is None and not any(
        (frame_dir / name).exists() for name in ("wallpaper-loaded", "wallpaper-error")
    ) and (frame_dir / "desktop-ready").exists():
        load_wallpapers()
    if reveal is None and t>=IMPACT_AT and (not args.switch or process is not None and process.poll() is not None):
        failed = bool(args.switch and process.returncode != 0)
        if args.switch and not failed and not (frame_dir / "wallpaper-loaded").exists():
            # An outdated switch.sh can exit without participating in readiness.
            failed = True
            print("Serpantinum wallpaper validation was not acknowledged.", file=log, flush=True)
        if not failed: sound()
        reveal=time.monotonic()
    if reveal is not None and time.monotonic()-reveal>=.9: app.quit()
    for win in windows: win.update()

shots=[(sc,capture(sc)) for sc in app.screens()]
if not shots:
    sys.exit("No Wayland outputs for the Serpantinum transition")
for sc,shot in shots: windows.append(Panel(sc,shot))
if not any(w.main for w in windows): windows[0].main=True
if args.switch:
    try:
        for window in windows:
            source = selected_wallpaper(window.output)
            if source.suffix.lower() not in VIDEO_EXTENSIONS:
                wallpaper_pixmap(source)
    except (OSError, ValueError) as error:
        message = f"{window.output}: {error}"
        (BASE / "serpantinum-switch.log").write_text(message + "\n")
        sys.exit(message)

with tempfile.TemporaryDirectory(prefix=".serpantinum-frames.", dir=BASE) as directory:
    frame_dir = Path(directory)
    (frame_dir / "outputs").write_text("".join(f"{window.output}\n" for window in windows))
    start=time.monotonic()
    for win in windows: win.show()
    timer=QTimer(); timer.timeout.connect(tick); timer.start(16)
    rc=app.exec()
    if log: log.close()

sys.exit(1 if failed else rc)
