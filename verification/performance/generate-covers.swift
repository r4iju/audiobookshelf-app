import Foundation
import CoreGraphics
import ImageIO
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (index,width) in [4000,3000].enumerated() {
 let h=4000
 let c=CGContext(data:nil,width:width,height:h,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
 for y in stride(from:0,to:h,by:20) { c.setFillColor(CGColor(red:0.1,green:CGFloat(90+y%100)/255,blue:0.6,alpha:1));c.fill(CGRect(x:0,y:y,width:width,height:20)) }
 let url=output.appendingPathComponent("\(index).jpg")
 let d=CGImageDestinationCreateWithURL(url as CFURL,"public.jpeg" as CFString,1,nil)!
 CGImageDestinationAddImage(d,c.makeImage()!,nil);CGImageDestinationFinalize(d)
}
