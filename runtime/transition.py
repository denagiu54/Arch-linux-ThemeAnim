from transition_guard import enter
enter(None)

import sys

if len(sys.argv) > 1 and sys.argv[1] == "leyzs":
    import runpy
    from pathlib import Path
    sys.argv.pop(1)
    runpy.run_path(str(Path(__file__).with_name("leyzs_transition.py")), run_name="__main__")

# Dispatch only Serpantinum; leave the approved Windows renderer intact.
if len(sys.argv) > 1 and sys.argv[1] == "serpantinum":
    import runpy
    from pathlib import Path
    sys.argv.pop(1)
    runpy.run_path(str(Path(__file__).with_name("serpantinum_transition.py")), run_name="__main__")
import math
import time
import numpy as np
import subprocess

from PySide6.QtWidgets import QApplication, QWidget
from PySide6.QtCore import Qt, QTimer, QRectF, QPointF
from PySide6.QtGui import (
    QPainter, QColor, QFont, QPen,
    QRadialGradient, QPolygonF, QPixmap
)

THEME = sys.argv[1] if len(sys.argv) > 1 else "win11"
SWITCH = "--switch" in sys.argv
BASE = __import__("pathlib").Path.home() / ".local/share/desktop-switcher"
MAIN = (BASE / "main-output").read_text().strip()
DURATION = 5.85 if THEME == "win11" and "--switch" in sys.argv else 5.0
COUNT = 850

COLORS = {
    "win11": (35, 145, 255),
    "serpantinum": (35, 240, 195),
    "leyzs": (210, 220, 240)
}

RGB = COLORS.get(THEME, COLORS["win11"])

def smooth(x):
    x = np.clip(x, 0, 1)
    return x*x*(3-2*x)

def color(alpha, rgb=RGB):
    return QColor(*rgb, int(np.clip(alpha, 0, 255)))

class Transition(QWidget):
    def __init__(self, screen, screenshot):
        super().__init__()
        self.main = screen.name() == MAIN
        self.screenshot = screenshot
        self.wallpaper = QPixmap(str(
            __import__("pathlib").Path.home() /
            ".local/share/desktop-switcher/assets/win11.png"
        ))
        self.setWindowTitle("Cinematic Desktop Transition")
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.WindowStaysOnTopHint
        )
        self.setCursor(Qt.CursorShape.BlankCursor)
        self.setGeometry(screen.geometry())
        self.winId()
        self.windowHandle().setScreen(screen)

        rng = np.random.default_rng(2026)

        self.angle = rng.uniform(0, math.tau, COUNT)
        self.radius = rng.uniform(0.5, 1.6, COUNT)
        self.depth = rng.uniform(0.2, 1, COUNT)
        self.speed = rng.uniform(0.2, 1.2, COUNT)
        self.delay = rng.uniform(0, 0.65, COUNT)
        self.phase = rng.uniform(0, math.tau, COUNT)
        self.u = rng.random(COUNT)
        self.v = rng.random(COUNT)
        self.panel = rng.integers(0, 4, COUNT)
        self.symbols = rng.choice(
            list("01ABCDEF+.:/"), COUNT
        )

        self.previous = None
        self.start = time.monotonic()

        self.timer = QTimer(self)
        self.timer.timeout.connect(self.tick)
        self.timer.start(16)

    def tick(self):
        if time.monotonic()-self.start >= DURATION:
            QApplication.instance().quit()
        else:
            self.update()

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(
            QPainter.RenderHint.Antialiasing
        )

        w, h = self.width(), self.height()
        cx, cy = w/2, h/2
        size = min(w,h)*0.25
        t = time.monotonic()-self.start

        p.fillRect(self.rect(), QColor(0,0,0))

        if THEME == "win11" and SWITCH and t >= 5.0:
            progress = min(1.0, (t-5.0)/0.85)
            ease = 1-(1-progress)**4

            zoom = 1.0+0.12*(1-ease)

            if not self.wallpaper.isNull():
                p.setRenderHint(
                    QPainter.RenderHint.SmoothPixmapTransform
                )

                scale = max(
                    w/self.wallpaper.width(),
                    h/self.wallpaper.height()
                )*zoom

                ww = self.wallpaper.width()*scale
                hh = self.wallpaper.height()*scale

                p.setOpacity(min(1.0, progress*7))

                p.drawPixmap(
                    QRectF(cx-ww/2, cy-hh/2, ww, hh),
                    self.wallpaper,
                    QRectF(self.wallpaper.rect())
                )

                p.setOpacity(1)

            return

        if t < 0.65:
            p.setOpacity(1-float(smooth(t/0.65)))
            if not self.screenshot.isNull():
                p.drawPixmap(self.rect(), self.screenshot)
            p.setOpacity(1)
            return

        if not self.main:
            return

        intro = float(smooth((t-0.65)/1.1))
        outro = float(1-smooth((t-4.45)/0.55))
        visibility = intro*outro

        formation = smooth(
            (t-0.65-self.delay)/2.65
        )

        energy = float(smooth((t-1.6)/1.8))
        solid = float(smooth((t-2.9)/1.25))

        # Atmospheric background glow
        glow = QRadialGradient(cx, cy, size*3.2)
        glow.setColorAt(
            0, color(48*energy*visibility)
        )
        glow.setColorAt(
            0.35, color(17*energy*visibility)
        )
        glow.setColorAt(1, QColor(0,0,0,0))
        p.fillRect(self.rect(), glow)

        # Perspective particle vortex
        angle = self.angle + t*self.speed*0.55

        radius = (
            self.radius*max(w,h)*0.7 /
            (1+t*0.35*self.depth)
        )

        sx = cx + np.cos(angle)*radius
        sy = cy + np.sin(angle)*radius*0.58

        # Exact symmetrical target geometry
        if THEME == "win11":
            gap = size*0.045
            panel_size = (size-gap)/2

            tx = (
                cx-size/2 +
                (self.panel % 2)*(panel_size+gap) +
                self.u*panel_size
            )
            ty = (
                cy-size/2 +
                (self.panel // 2)*(panel_size+gap) +
                self.v*panel_size
            )

        elif THEME == "serpantinum":
            ring = self.panel % 3
            rr = size*(0.34+ring*0.17)
            aa = self.angle + t*0.45

            tx = cx + np.cos(aa)*rr
            ty = cy + np.sin(aa)*rr

        else:
            tx = cx + (self.u-0.5)*size*2.6
            ty = (
                cy+size*0.35 -
                np.abs(np.sin(self.u*math.pi*3))
                *size*0.85
            )

        turbulence = (
            np.sin(self.phase+t*4) *
            (1-formation)*18
        )

        x = sx*(1-formation)+tx*formation+turbulence
        y = sy*(1-formation)+ty*formation

        if self.previous is None:
            self.previous = (x.copy(),y.copy())

        px, py = self.previous

        # Motion trails
        for i in range(0, COUNT, 5):
            alpha = (
                65*self.depth[i] * float(smooth((t-0.65-self.delay[i])/0.8)) *
                (1-formation[i])*visibility
            )

            p.setPen(QPen(color(alpha), 1.1))
            p.drawLine(
                QPointF(px[i],py[i]),
                QPointF(x[i],y[i])
            )

        self.previous = (x.copy(),y.copy())

        # Gradual ASCII-to-light transformation
        for i in range(COUNT):
            f = float(formation[i])
            pulse = 0.8+0.2*math.sin(
                t*5+self.phase[i]
            )

            alpha = (
                (90+165*self.depth[i]) *
                visibility*pulse*float(smooth((t-0.65-self.delay[i])/0.8))
            )

            if THEME == "win11":
                alpha *= 1-float(smooth((t-2.8)/0.9))

            glyph = float(1-smooth((f-0.4)/0.6))
            dot = 1-glyph

            if i % 6 == 0 and glyph > 0.03:
                font = QFont("monospace")
                font.setPixelSize(
                    max(3,int(6+9*glyph))
                )
                p.setFont(font)
                p.setPen(color(alpha*glyph))

                p.drawText(
                    QPointF(x[i],y[i]),
                    str(self.symbols[i])
                )

            if dot > 0.01 or i % 6 != 0:
                r = 0.6+self.depth[i]*1.6

                p.setPen(Qt.PenStyle.NoPen)
                p.setBrush(color(alpha*0.12))
                p.drawEllipse(
                    QPointF(x[i],y[i]),r*3,r*3
                )

                p.setBrush(color(alpha))
                p.drawEllipse(
                    QPointF(x[i],y[i]),r,r
                )

        # Slowly blend the particles into the logo
        if THEME == "win11":
            gap = size*0.045
            panel_size = (size-gap)/2

            for i in range(4):
                xx = cx-size/2+(i%2)*(panel_size+gap)
                yy = cy-size/2+(i//2)*(panel_size+gap)

                rect = QRectF(
                    xx,yy,panel_size,panel_size
                )

                p.setBrush(Qt.BrushStyle.NoBrush)

                for width in range(24,0,-4):
                    p.setPen(QPen(
                        color(
                            solid*visibility*22/width
                        ),
                        width
                    ))
                    p.drawRect(rect)

                p.setPen(Qt.PenStyle.NoPen)
                p.setBrush(
                    color(255*solid*visibility)
                )
                p.drawRect(rect)

        elif THEME == "serpantinum":
            p.setBrush(Qt.BrushStyle.NoBrush)

            for i in range(3):
                rr = size*(0.34+i*0.17)

                rect = QRectF(
                    cx-rr,cy-rr,rr*2,rr*2
                )

                for j in range(3):
                    p.setPen(QPen(
                        color(220*solid*visibility),
                        2+i
                    ))

                    rotation = int(
                        (t*85*(1 if i%2 else -1)
                        +j*120)*16
                    )

                    p.drawArc(
                        rect,rotation,75*16
                    )

            p.setPen(QPen(
                color(240*solid*visibility),2
            ))

            points = [
                QPointF(cx,cy-size*0.22),
                QPointF(cx+size*0.18,cy),
                QPointF(cx,cy+size*0.22),
                QPointF(cx-size*0.18,cy)
            ]

            p.drawPolygon(QPolygonF(points))

        else:
            p.setPen(QPen(
                color(220*solid*visibility),2
            ))

            points = []

            for u in np.linspace(0,1,160):
                xx = cx+(u-0.5)*size*2.6
                yy = (
                    cy+size*0.35 -
                    abs(math.sin(u*math.pi*3))
                    *size*0.85
                )
                points.append(QPointF(xx,yy))

            p.drawPolyline(QPolygonF(points))

    def keyPressEvent(self,event):
        if event.key() == Qt.Key.Key_Escape:
            QApplication.instance().quit()

app = QApplication(sys.argv)
windows = []
screenshots = {}

for screen in app.screens():
    pix = QPixmap()
    result = subprocess.run(
        ["grim", "-o", screen.name(), "-"],
        capture_output=True
    )
    if result.returncode == 0:
        pix.loadFromData(result.stdout)
    screenshots[screen.name()] = pix

for screen in app.screens():
    window = Transition(screen, screenshots[screen.name()])
    windows.append(window)
    window.showFullScreen()

if SWITCH:
    def change_theme():
        subprocess.Popen(
            ["bash", str(BASE / "switch.sh"), THEME],
            stdout=open(BASE / "switch.log", "w"),
            stderr=subprocess.STDOUT
        )

    def startup_sound():
        if THEME == "win11" and (BASE / "startup.wav").is_file():
            subprocess.Popen(
                ["mpv", "--no-video", "--really-quiet",
                 "--volume=60", str(BASE / "startup.wav")],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )

    QTimer.singleShot(1800, change_theme)
    QTimer.singleShot(4100, startup_sound)

sys.exit(app.exec())
