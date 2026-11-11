import CoreGraphics
var checks = 0, failures = 0
func check(_ ok: Bool, _ title: String) { checks += 1; if !ok { failures += 1; print("FAIL", title) } }
let vga = CGSize(width: 1280, height: 1024), hd = CGSize(width: 1920, height: 1080)
var s = CorrectionSettings()
var r = CorrectionSettings.layout(frame: vga, desktop: hd, settings: s)
check(r == CGRect(x: 0, y: 152, width: 1280, height: 720), "16:9 en 1280×1024: 1280×720 con 152 px negros arriba y abajo \(r)")
s.left = 40; s.right = 80; s.top = 30; s.bottom = 60
r = CorrectionSettings.layout(frame: vga, desktop: hd, settings: s)
check(r.width == 1160 && abs(r.height - 652.5) <= 1 && r.minX == 40 && abs(r.midY - (30 + (1024 - 90) / 2)) <= 1, "márgenes independientes \(r)")
s = CorrectionSettings(); s.scale = 0.5
r = CorrectionSettings.layout(frame: vga, desktop: hd, settings: s)
check(r.size == CGSize(width: 640, height: 360) && r.midX == 640 && r.midY == 512, "escala global centrada \(r)")
s.offsetX = 100; s.offsetY = -50
r = CorrectionSettings.layout(frame: vga, desktop: hd, settings: s)
check(r.minX == 420 && r.minY == 282, "desplazamiento horizontal y vertical \(r)")
s.offsetX = 9999; s.offsetY = 9999
r = CorrectionSettings.layout(frame: vga, desktop: hd, settings: s)
check(r.maxX == 1280 && r.maxY == 1024 && r.width == 640, "desplazar al límite no corta \(r)")
s = CorrectionSettings(); s.scale = 1.5
r = CorrectionSettings.layout(frame: vga, desktop: hd, settings: s)
check(r.width <= 1280 && r.height <= 1024 && r.minX >= 0 && r.minY >= 0, "escala máxima no corta \(r)")
for (w, h) in CorrectionSettings.desktopSizes {
    for scale in [0.3, 0.77, 1.0, 1.5] { for m in [0.0, 37, 400] { for o in [-700.0, 0, 333] {
        var t = CorrectionSettings(); t.desktopWidth = w; t.desktopHeight = h; t.scale = scale; t.left = m; t.top = m / 2; t.right = m / 3; t.bottom = m; t.offsetX = o; t.offsetY = -o
        let q = CorrectionSettings.layout(frame: vga, desktop: CGSize(width: w, height: h), settings: t)
        let ratio = (q.width / q.height) / (CGFloat(w) / CGFloat(h))
        check(q.minX >= 0 && q.minY >= 0 && q.maxX <= 1280 && q.maxY <= 1024 && abs(ratio - 1) < 0.01 && q.width >= 1, "nunca corta ni deforma \(w)x\(h) s\(scale) m\(m) o\(o): \(q)")
    }}}
}
var bad = CorrectionSettings(); bad.scale = .nan; bad.left = .infinity; bad.offsetX = -.infinity
r = CorrectionSettings.layout(frame: vga, desktop: hd, settings: bad)
check(r.width > 0 && r.minX >= 0 && r.maxX <= 1280, "valores inválidos no rompen el cálculo \(r)")
var fit = CorrectionSettings(); fit.scale = 0.6; fit.offsetX = 50; fit.left = 20; fit.centerAndFit()
check(fit.scale == 1 && fit.offsetX == 0 && fit.left == 20, "Centrar y ajustar conserva los márgenes")
// A 16:9 TV that stretches the 5:4 signal: the 16:9 desktop fills the whole signal.
var tvs = CorrectionSettings(); tvs.screenAspect = 16.0 / 9
r = CorrectionSettings.layout(frame: vga, desktop: hd, settings: tvs)
check(r == CGRect(x: 0, y: 0, width: 1280, height: 1024), "TV 16:9 que estira la señal: el escritorio ocupa toda la señal \(r)")
r = CorrectionSettings.layout(frame: vga, desktop: hd, settings: CorrectionSettings(), physicalAspect: 16.0 / 9)
check(r == CGRect(x: 0, y: 0, width: 1280, height: 1024), "automático usa el tamaño físico del monitor \(r)")
var tv10 = tvs; tv10.desktopHeight = 1200
r = CorrectionSettings.layout(frame: vga, desktop: CGSize(width: 1920, height: 1200), settings: tv10)
let k = CorrectionSettings.stretch(frame: vga, settings: tv10, physicalAspect: nil)
check(abs((r.width * k / r.height) / 1.6 - 1) < 0.01 && r.minX > 0 && r.minY == 0, "16:10 en TV 16:9: bordes a los lados y proporción correcta en pantalla \(r)")
var five = CorrectionSettings(); five.screenAspect = 1.25
check(CorrectionSettings.layout(frame: vga, desktop: hd, settings: five, physicalAspect: 16.0 / 9) == CGRect(x: 0, y: 152, width: 1280, height: 720), "5:4 elegido a mano manda sobre el automático")
print("RESULT \(checks) checks \(failures) failures"); exit(failures == 0 ? 0 : 1)
