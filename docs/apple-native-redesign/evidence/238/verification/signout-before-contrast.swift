import AppKit
let path="/tmp/native238-signout-before-0846b353df42.png"
let rep=NSBitmapImageRep(data:try Data(contentsOf:URL(fileURLWithPath:path)))!
func rgb(_ x:Int,_ y:Int)->[Int]{let c=rep.colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!;return [c.redComponent,c.greenComponent,c.blueComponent].map{Int(($0*255).rounded())}}
func lum(_ rgb:[Int])->Double{let v=rgb.map{Double($0)/255}.map{$0<=0.04045 ? $0/12.92 : pow(($0+0.055)/1.055,2.4)};return v[0]*0.2126+v[1]*0.7152+v[2]*0.0722}
let scale=Double(rep.pixelsWide)/3840
let bg=rgb(Int(1500*scale),Int(1850*scale))
for (name,box) in [("focusedSignOutLabel",[622,1840,840,1920])]{
 let box=box.map{Int(Double($0)*scale)}
 var counts=[[Int]:Int]()
 for y in box[1]..<box[3]{for x in box[0]..<box[2]{counts[rgb(x,y),default:0]+=1}}
 let candidates=counts.sorted{$0.value>$1.value}.filter{$0.key != bg && $0.key.min()!>25}.prefix(4)
 print(name,"background",bg,"dominantNonBackground",candidates.map{(rgb:$0.key,pixels:$0.value,contrast:(max(lum($0.key),lum(bg))+0.05)/(min(lum($0.key),lum(bg))+0.05))})
}
