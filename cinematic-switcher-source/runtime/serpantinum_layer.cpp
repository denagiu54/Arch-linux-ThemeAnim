#include <LayerShellQt/Window>
#include <QWindow>

extern "C" void configure_cinematic(QWindow *window, QScreen *screen)
{
    using LayerShellQt::Window;
    auto *layer = Window::get(window);
    layer->setScope(QStringLiteral("serpantinum-cinematic"));
    layer->setLayer(Window::LayerOverlay);
    layer->setAnchors(Window::Anchors(Window::AnchorTop) | Window::AnchorBottom |
                      Window::AnchorLeft | Window::AnchorRight);
    layer->setExclusiveZone(-1);
    layer->setKeyboardInteractivity(Window::KeyboardInteractivityOnDemand);
    layer->setScreen(screen);
    layer->setDesiredSize(QSize(0, 0));
}
