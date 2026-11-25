from transition_guard import enter
enter('leyzs')

import sys, time, math, subprocess, shutil, argparse
from pathlib import Path
import numpy as np
from PySide6.QtWidgets import QApplication, QWidget
from PySide6.QtCore import Qt, QTimer, QRectF, QPointF
from PySide6.QtGui import QPainter, QColor, QPen, QFont, QPixmap, QLinearGradient, QPolygonF
BASE=Path(__file__).resolve().parent
MAIN = (BASE / "main-output").read_text().strip()
parser=argparse.ArgumentParser(); parser.add_argument('--switch',action='store_true'); args=parser.parse_args()
app=QApplication([sys.argv[0]])
rng=np.random.default_rng(42); N=850
u=rng.random(N); v=rng.random(N); speed=rng.uniform(.15,.55,N); delay=rng.uniform(0,.65,N); layer=rng.integers(0,3,N)
def ease(x):
    x=np.clip(x,0,1); return x*x*(3-2*x)
def ink(a): return QColor(218,225,235,int(np.clip(a,0,255)))
def ridge(x,j):
    return .68+j*.09-(.19-j*.035)*(np.abs(np.sin(x*8.4+j*1.7))+.35*np.sin(x*23+j)+.12*np.sin(x*61+j))
def capture(sc):
    pix=QPixmap()
    try:
        r=subprocess.run(['grim','-o',sc.name(),'-'],capture_output=True,timeout=3)
        if r.returncode==0: pix.loadFromData(r.stdout)
    except (OSError,subprocess.TimeoutExpired): pass
    return pix
wall=QPixmap(str(BASE/'assets/leyzs.png'))
start=0; reveal=None; process=None; log=None; failed=False; windows=[]
class Panel(QWidget):
    def __init__(self,sc,shot):
        super().__init__(); self.shot=shot; self.main=sc.name()==MAIN
        self.setWindowTitle('Cinematic Desktop Transition'); self.setWindowFlags(Qt.WindowType.FramelessWindowHint|Qt.WindowType.WindowStaysOnTopHint); self.setCursor(Qt.CursorShape.BlankCursor); self.setGeometry(sc.geometry()); self.winId(); self.windowHandle().setScreen(sc)
    def paintEvent(self,event):
        p=QPainter(self); p.setRenderHint(QPainter.RenderHint.Antialiasing); p.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)
        w,h=self.width(),self.height(); t=time.monotonic()-start
        p.fillRect(self.rect(),QColor(0,0,0))
        if t<.65:
            p.setOpacity(1-float(ease(t/.65))); p.drawPixmap(self.rect(),self.shot); return
        if reveal is not None:
            q=float(ease((time.monotonic()-reveal)/1.05)); pix=wall if not wall.isNull() and not failed else self.shot
            if not pix.isNull():
                k=max(w/pix.width(),h/pix.height())*(1+.08*(1-q)); ww,hh=pix.width()*k,pix.height()*k
                p.setOpacity(q); p.drawPixmap(QRectF((w-ww)/2,(h-hh)/2,ww,hh),pix,QRectF(pix.rect()))
            return
        if not self.main: return
        intro=float(ease((t-.65)/.8)); solid=float(ease((t-2.7)/1.2)); f=ease((t-1.25-delay)/2.1)
        # Layered mountain silhouettes, with fine silver ridgelines.
        for j in range(3):
            xx=np.linspace(0,1,240); yy=ridge(xx,j)
            points=[QPointF(float(x*w),float(y*h)) for x,y in zip(xx,yy)]
            poly=QPolygonF(points+[QPointF(w,h),QPointF(0,h)])
            p.setPen(Qt.PenStyle.NoPen); p.setBrush(QColor(13+j*9,15+j*9,19+j*10,int(245*solid))); p.drawPolygon(poly)
            p.setBrush(Qt.BrushStyle.NoBrush); p.setPen(QPen(ink((100+j*35)*solid),1.2)); p.drawPolyline(QPolygonF(points))
        # Rain resolves into the mountain contours.
        x=u*w; y=((v+(t-.65)*speed)%1.2-.1)*h; ty=ridge(u,layer)*h+rng_static*(1-f)*30
        y=y*(1-f)+ty*f
        p.setFont(QFont('monospace',10))
        for i in range(N):
            alpha=(80+120*v[i])*intro*float(ease((t-.65-delay[i])/.6))*(1-.65*solid)
            if i%5==0 and f[i]<.65:
                p.setPen(ink(alpha)); p.drawText(QPointF(x[i],y[i]),'01.:+/'[i%6])
                p.setPen(QPen(ink(alpha*.22),1)); p.drawLine(QPointF(x[i],y[i]-18),QPointF(x[i],y[i]-5))
            else:
                p.setPen(Qt.PenStyle.NoPen); p.setBrush(ink(alpha)); p.drawEllipse(QPointF(x[i],y[i]),.7+v[i],.7+v[i])
        for j in range(3):
            yy=h*(.62+j*.09)+math.sin(t*.6+j)*h*.025
            g=QLinearGradient(0,yy-45,0,yy+45); g.setColorAt(0,ink(0)); g.setColorAt(.5,ink(19*solid)); g.setColorAt(1,ink(0)); p.fillRect(QRectF(0,yy-45,w,90),g)
        font=QFont('sans-serif',18); font.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing,8); p.setFont(font); p.setPen(ink(230*solid)); p.drawText(QRectF(0,h*.23,w,60),Qt.AlignmentFlag.AlignCenter,'L E Y Z S')
    def keyPressEvent(self,event):
        if event.key()==Qt.Key.Key_Escape and process is None: app.quit()
rng_static=rng.normal(0,1,N)
def tick():
    global process,log,reveal,failed
    t=time.monotonic()-start
    if args.switch and process is None and t>=1.8:
        log=open(BASE/'leyzs-switch.log','w'); process=subprocess.Popen(['bash',str(BASE/'switch.sh'),'leyzs'],stdout=log,stderr=subprocess.STDOUT)
    if reveal is None and t>=4.65 and (not args.switch or process is not None and process.poll() is not None):
        failed=bool(args.switch and process.returncode!=0); reveal=time.monotonic()
        if not failed and shutil.which('mpv') and (BASE/'leyzs.wav').is_file(): subprocess.Popen(['mpv','--no-video','--really-quiet','--volume=45',str(BASE/'leyzs.wav')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if reveal is not None and time.monotonic()-reveal>=1.1: app.quit()
    for win in windows: win.update()
shots=[(sc,capture(sc)) for sc in app.screens()]
for sc,shot in shots: windows.append(Panel(sc,shot))
if windows and not any(w.main for w in windows): windows[0].main=True
start=time.monotonic()
for win in windows: win.showFullScreen()
timer=QTimer(); timer.timeout.connect(tick); timer.start(16)
rc=app.exec()
if log: log.close()
sys.exit(1 if failed else rc)
