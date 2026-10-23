import AVECore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Préparation des photos SUR L'IPHONE, avec ImageIO (même code sur iOS et dans les tests sur Mac) :
/// - le moteur refuse le HEIC des iPhone : toute photo part en JPEG, sans rien demander ;
/// - plus de 10 Mo : réduite (grand côté 4096 px, puis qualité moindre) plutôt que refusée ;
/// - « Recadrer » : coupe au centre vers carré, portrait ou paysage, sans IA ni envoi.
public enum ImageProcessing {
    public struct Prepared: Sendable, Equatable {
        public let data: Data
        public let mime: String
        public let width: Int
        public let height: Int
    }

    /// Grand côté maximal d'une photo envoyée : au-delà, le moteur la réduirait de toute façon (sortie 4K = 3840 px).
    public static let maxPixelSize = 4096

    public static func dimensions(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        // Orientation EXIF 5 à 8 : l'image est tournée d'un quart de tour à l'affichage.
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? (h, w) : (w, h)
    }

    /// Un PNG léger passe tel quel ; tout le reste (JPEG avec ses métadonnées EXIF, HEIC, trop lourd, trop grand) est
    /// réencodé en JPEG redressé, sans métadonnées.
    public static func prepareForUpload(_ data: Data, maxBytes: Int = MediaLimits.maxUploadBytes) -> Prepared? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source).map({ $0 as String }),
              let size = dimensions(of: data) else { return nil }
        if type == UTType.png.identifier, data.count <= maxBytes, max(size.width, size.height) <= maxPixelSize {
            return Prepared(data: data, mime: "image/png", width: size.width, height: size.height)
        }
        for quality in [0.9, 0.8, 0.65, 0.5] {
            guard let image = thumbnail(source, maxPixelSize: maxPixelSize),
                  let jpeg = encodeJPEG(image, quality: quality) else { return nil }
            if jpeg.count <= maxBytes {
                return Prepared(data: jpeg, mime: "image/jpeg", width: image.width, height: image.height)
            }
        }
        return nil
    }

    /// Coupe au centre vers le format demandé (carré 1:1, portrait 9:16, paysage 16:9), en JPEG redressé.
    public static func crop(_ data: Data, to aspect: ImageSize) -> Prepared? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = thumbnail(source, maxPixelSize: maxPixelSize) else { return nil }
        let rect = centerCrop(width: image.width, height: image.height, aspect: aspect)
        guard let cropped = image.cropping(to: rect), let jpeg = encodeJPEG(cropped, quality: 0.9) else { return nil }
        return Prepared(data: jpeg, mime: "image/jpeg", width: cropped.width, height: cropped.height)
    }

    /// Le plus grand rectangle centré au bon rapport.
    public static func centerCrop(width: Int, height: Int, aspect: ImageSize) -> CGRect {
        let ratio: Double
        switch aspect {
        case .square: ratio = 1
        case .portrait: ratio = 9.0 / 16.0
        case .landscape: ratio = 16.0 / 9.0
        }
        let w = Double(width), h = Double(height)
        let cropW = min(w, (h * ratio).rounded(.down))
        let cropH = min(h, (cropW / ratio).rounded(.down))
        return CGRect(x: ((w - cropW) / 2).rounded(.down), y: ((h - cropH) / 2).rounded(.down), width: cropW, height: cropH)
    }

    /// Aperçu léger pour la conversation (les images 4K ne sont jamais décodées en entier à l'écran).
    public static func previewImage(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(source, maxPixelSize: maxPixelSize)
    }

    // MARK: Interne

    /// Décodage redressé (orientation EXIF appliquée) et réduit si besoin.
    private static func thumbnail(_ source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// JPEG sans métadonnées : la position GPS et l'appareil d'une photo ne partent pas chez le moteur.
    private static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
