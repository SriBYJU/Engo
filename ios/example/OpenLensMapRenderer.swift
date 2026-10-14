import Foundation
import UIKit
import MapKit
import CoreLocation

/// Creates an actual MapKit street-map snapshot sized for the ENGO 3 optics.
/// MapKit does NOT include custom overlays in MKMapSnapshotter output, so draw
/// route/turn markers into the image using snapshot.point(for:) coordinates.
final class OpenLensMapRenderer {
    private var snapshotter: MKMapSnapshotter?
    private(set) var requestID = 0

    func cancel() {
        requestID += 1
        snapshotter?.cancel()
        snapshotter = nil
    }

    /// Renders a static *route preview*, not a live or safety-critical AR map.
    func snapshot(route: MKRoute, step: MKRoute.Step,
                  overview: Bool, currentLocation: CLLocationCoordinate2D?,
                  completion: @escaping (UIImage?, String?) -> Void) {
        cancel()
        let ticket = requestID
        let focusPolyline = overview ? route.polyline : step.polyline
        let effectivePolyline = focusPolyline.pointCount > 0 ? focusPolyline : route.polyline
        guard effectivePolyline.pointCount > 0 else {
            completion(nil, "The route has no coordinates to draw.")
            return
        }

        let options = MKMapSnapshotter.Options()
        options.size = CGSize(width: OpenLensDisplayGeometry.textImageWidth,
                              height: OpenLensDisplayGeometry.textImageHeight)
        options.scale = 1
        options.mapType = .standard
        options.showsBuildings = false
        options.pointOfInterestFilter = .excludingAll
        let rect = effectivePolyline.boundingMapRect
        let centerPoint = MKMapPoint(x: rect.midX, y: rect.midY)
        let center = centerPoint.coordinate
        let north = MKMapPoint(x: rect.midX, y: rect.minY).coordinate
        let south = MKMapPoint(x: rect.midX, y: rect.maxY).coordinate
        let west = MKMapPoint(x: rect.minX, y: rect.midY).coordinate
        let east = MKMapPoint(x: rect.maxX, y: rect.midY).coordinate
        let latDistance = CLLocation(latitude: north.latitude, longitude: north.longitude)
            .distance(from: CLLocation(latitude: south.latitude, longitude: south.longitude))
        let lonDistance = CLLocation(latitude: west.latitude, longitude: west.longitude)
            .distance(from: CLLocation(latitude: east.latitude, longitude: east.longitude))
        // Give narrow/short turns surrounding street context.
        options.region = MKCoordinateRegion(center: center,
            latitudinalMeters: min(25000, max(320, latDistance * 2.3)),
            longitudinalMeters: min(25000, max(320, lonDistance * 2.3)))

        let worker = MKMapSnapshotter(options: options)
        snapshotter = worker
        worker.start { [weak self] snapshot, error in
            guard let self = self, ticket == self.requestID else { return }
            self.snapshotter = nil
            guard let snapshot = snapshot else {
                completion(nil, error?.localizedDescription ?? "Unable to load map tiles.")
                return
            }
            let image = Self.render(snapshot: snapshot, route: route, step: step,
                                    overview: overview, currentLocation: currentLocation)
            completion(image, image == nil ? "Map rendering failed." : nil)
        }
    }

    private static func render(snapshot: MKMapSnapshotter.Snapshot,
                               route: MKRoute, step: MKRoute.Step,
                               overview: Bool, currentLocation: CLLocationCoordinate2D?) -> UIImage? {
        let width = OpenLensDisplayGeometry.textImageWidth
        let height = OpenLensDisplayGeometry.textImageHeight
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let uiImage = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            let frame = CGRect(x: 0, y: 0, width: width, height: height)
            snapshot.image.draw(in: frame)
            // Keep the map recognizable, while ensuring the route survives a
            // 1-bit conversion. Plain photo-style thresholding loses streets.
            UIColor.black.withAlphaComponent(0.34).setFill()
            UIRectFill(frame)
            let drawPolyline: (MKPolyline, CGFloat, UIColor) -> Void = { polyline, thickness, color in
                guard polyline.pointCount > 0 else { return }
                let coords = polyline.points()
                let path = UIBezierPath()
                for i in 0..<polyline.pointCount {
                    let at = snapshot.point(for: coords[i].coordinate)
                    if i == 0 { path.move(to: at) }
                    else { path.addLine(to: at) }
                }
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.lineWidth = thickness
                color.setStroke()
                path.stroke()
            }
            // Dark outline first, then a bright central walking route.
            drawPolyline(route.polyline, 7, .black)
            drawPolyline(route.polyline, 3, UIColor(white: 0.80, alpha: 1))
            drawPolyline(step.polyline, 11, .black)
            drawPolyline(step.polyline, 5.5, .white)

            if let current = currentLocation, CLLocationCoordinate2DIsValid(current) {
                let dot = snapshot.point(for: current)
                let ring = UIBezierPath(ovalIn: CGRect(x: dot.x - 8, y: dot.y - 8, width: 16, height: 16))
                ring.lineWidth = 3
                UIColor.white.setFill()
                ring.fill()
                UIColor.black.setStroke()
                ring.stroke()
            }
            if step.polyline.pointCount > 0 {
                let end = step.polyline.points()[step.polyline.pointCount - 1].coordinate
                let pt = snapshot.point(for: end)
                let target = UIBezierPath(ovalIn: CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16))
                target.lineWidth = 3
                UIColor.black.setFill()
                target.fill()
                UIColor.white.setStroke()
                target.stroke()
            }
            // Miniature compass badge; explicit N makes map orientation clear.
            let badge = CGRect(x: width - 42, y: 9, width: 33, height: 32)
            UIColor.black.setFill()
            UIBezierPath(roundedRect: badge, cornerRadius: 8).fill()
            ("N" as NSString).draw(at: CGPoint(x: width - 34, y: 12), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.white
            ])
        }
        return makeMonochrome(uiImage)
    }

    /// 1-bit pixels are required to make a useful optical mini-map. Normalize
    /// to standard device-RGB after thresholding to satisfy the SDK assertion.
    private static func makeMonochrome(_ image: UIImage) -> UIImage? {
        guard let source = OpenLensRGBImage.normalize(image), let cg = source.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        let flags = CGBitmapInfo.byteOrder32Big.rawValue |
                    CGImageAlphaInfo.premultipliedLast.rawValue
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let length = width * height * 4
        var pixels = [UInt8](repeating: 0, count: length)
        let constructed: CGImage? = pixels.withUnsafeMutableBytes { raw in
            guard let address = raw.baseAddress,
                  let context = CGContext(data: address, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: colorSpace, bitmapInfo: flags) else { return nil }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            for i in stride(from: 0, to: length, by: 4) {
                let lum = Double(pixels[i]) * 0.2126 +
                          Double(pixels[i + 1]) * 0.7152 +
                          Double(pixels[i + 2]) * 0.0722
                // Very bright route/roads survive; background is dark.
                let bit: UInt8 = lum >= 125 ? 255 : 0
                pixels[i] = bit
                pixels[i + 1] = bit
                pixels[i + 2] = bit
                pixels[i + 3] = 255
            }
            return context.makeImage()
        }
        guard let result = constructed else { return nil }
        return UIImage(cgImage: result, scale: 1, orientation: .up)
    }
}
