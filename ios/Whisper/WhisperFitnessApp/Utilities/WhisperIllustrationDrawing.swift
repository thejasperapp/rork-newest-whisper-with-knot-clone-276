import SwiftUI

/// Authored silhouettes share pastel pigments and fine rounded linework only.
struct WhisperIllustrationDrawing {
    let context: GraphicsContext
    let ink: Color
    private let peach = Color(red: 1, green: 0.78, blue: 0.61)
    private let pink = Color(red: 0.98, green: 0.76, blue: 0.81)
    private let butter = Color(red: 1, green: 0.89, blue: 0.58)
    private let paper = Color(red: 1, green: 0.96, blue: 0.87)
    private let sage = Color(red: 0.76, green: 0.85, blue: 0.76)

    func draw(_ kind: WhisperIllustrationKind) {
        switch kind {
        case .messages: messages()
        case .replies: replies()
        case .groups: groups()
        case .posts: posts()
        case .photos: photos()
        case .waves: waves()
        case .search: search()
        case .people: people()
        case .saved: saved()
        case .notes: notes()
        case .audio: audio()
        case .calendar: calendar()
        case .activity: activity()
        case .files: files()
        case .fitness: fitness()
        case .food: food()
        case .shopping: shopping()
        case .places: places()
        case .safety: safety()
        case .stickers: stickers()
        case .awards: awards()
        case .map: map()
        case .ideas: ideas()
        case .studio: studio()
        case .live: live()
        case .likes: likes()
        case .reposts: reposts()
        }
    }

    private func line(_ points: [CGPoint], close: Bool = false, fill: Color? = nil) {
        var path = Path(); path.addLines(points); if close { path.closeSubpath() }
        shape(path, fill: fill)
    }
    private func shape(_ path: Path, fill: Color? = nil) {
        if let fill { context.fill(path, with: .linearGradient(Gradient(colors: [fill, fill.opacity(0.8)]), startPoint: CGPoint(x: 70, y: 25), endPoint: CGPoint(x: 235, y: 146))) }
        context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 6, _ fill: Color? = nil) {
        shape(Path(roundedRect: CGRect(x: x,y: y,width: w,height: h), cornerRadius: r), fill: fill)
    }
    private func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: Color? = nil) {
        shape(Path(ellipseIn: CGRect(x:x,y:y,width:w,height:h)), fill: fill)
    }
    private func curve(_ start: CGPoint, _ end: CGPoint, _ c1: CGPoint, _ c2: CGPoint) {
        var p = Path(); p.move(to:start); p.addCurve(to:end,control1:c1,control2:c2); shape(p)
    }
    private func ground(_ x: CGFloat = 58, _ width: CGFloat = 190) {
        context.fill(Path(ellipseIn:CGRect(x:x,y:142,width:width,height:7)),with:.color(peach.opacity(0.18)))
    }
    private func glint(_ x: CGFloat, _ y: CGFloat) {
        line([CGPoint(x:x-5,y:y),CGPoint(x:x+5,y:y)])
        line([CGPoint(x:x,y:y-5),CGPoint(x:x,y:y+5)])
    }

    private func messages() {
        ground(72,160)
        line([.init(x:78,y:83),.init(x:143,y:36),.init(x:218,y:83),.init(x:218,y:139),.init(x:78,y:139)],close:true,fill:pink)
        rect(104,58,89,67,5,paper)
        line([.init(x:78,y:83),.init(x:145,y:121),.init(x:218,y:83)])
        line([.init(x:78,y:139),.init(x:127,y:108)])
        line([.init(x:218,y:139),.init(x:166,y:108)])
        line([.init(x:158,y:47),.init(x:248,y:24),.init(x:213,y:82),.init(x:198,y:57)],close:true,fill:butter)
        line([.init(x:198,y:57),.init(x:248,y:24),.init(x:185,y:67),.init(x:187,y:80),.init(x:198,y:69)])
        curve(.init(x:45,y:104),.init(x:102,y:25),.init(x:91,y:105),.init(x:45,y:25))
    }
    private func replies() {
        shape(bubble(x:53,y:29,w:123,h:72,tailLeft:true),fill:butter)
        shape(bubble(x:136,y:74,w:111,h:60,tailLeft:false),fill:pink)
        for x: CGFloat in [82,109,136] { oval(x,56,6,6,peach) }
        line([.init(x:158,y:94),.init(x:216,y:94)])
        line([.init(x:158,y:107),.init(x:196,y:107)])
        glint(220,39)
    }
    private func bubble(x:CGFloat,y:CGFloat,w:CGFloat,h:CGFloat,tailLeft:Bool) -> Path {
        var p = Path(roundedRect:CGRect(x:x,y:y,width:w,height:h),cornerRadius:17)
        let tx = tailLeft ? x+20 : x+w-32
        p.addLines([.init(x:tx,y:y+h-1),.init(x:tx+3,y:y+h+17),.init(x:tx+24,y:y+h-1)])
        return p
    }
    private func groups() {
        for (x,y,fill) in [(CGFloat(72),CGFloat(44),butter),(CGFloat(151),CGFloat(20),pink),(CGFloat(214),CGFloat(61),sage)] {
            line([.init(x:x,y:y),.init(x:x+23,y:y+25),.init(x:x,y:y+55),.init(x:x-23,y:y+25)],close:true,fill:fill)
            curve(.init(x:x,y:y+55),.init(x:147,y:150),.init(x:x+30,y:y+85),.init(x:100,y:135))
            line([.init(x:x-23,y:y+25),.init(x:x+23,y:y+25)])
        }
        glint(108,22)
    }
    private func posts() {
        ground()
        rect(70,48,109,93,8,pink); rect(85,34,109,97,8,paper)
        line([.init(x:104,y:61),.init(x:167,y:61)]); line([.init(x:104,y:77),.init(x:156,y:77)])
        line([.init(x:104,y:93),.init(x:148,y:93)])
        var feather = Path(); feather.move(to:.init(x:184,y:118)); feather.addCurve(to:.init(x:238,y:22),control1:.init(x:178,y:60),control2:.init(x:212,y:14)); feather.addCurve(to:.init(x:184,y:118),control1:.init(x:251,y:71),control2:.init(x:214,y:97)); shape(feather,fill:butter)
        line([.init(x:174,y:137),.init(x:229,y:40)])
        glint(53,29)
    }
    private func photos() {
        curve(.init(x:31,y:30),.init(x:270,y:27),.init(x:125,y:64),.init(x:201,y:48))
        rect(61,47,71,86,3,paper); rect(158,57,78,84,3,pink)
        rect(68,54,57,58,1,sage); rect(165,64,64,56,1,butter)
        line([.init(x:68,y:106),.init(x:89,y:77),.init(x:109,y:100),.init(x:118,y:88),.init(x:125,y:105)])
        oval(177,73,12,12,peach)
        line([.init(x:165,y:115),.init(x:196,y:88),.init(x:229,y:115)])
        rect(87,37,7,20,2,butter); rect(191,40,7,22,2,peach)
    }
    private func waves() {
        ground(56,194)
        oval(74,30,100,100,pink); oval(116,72,16,16,paper)
        for angle in [0.0,72,144,216,288] {
            let rad = angle * .pi / 180
            oval(117+CGFloat(cos(rad))*30,73+CGFloat(sin(rad))*30,14,14,paper)
        }
        curve(.init(x:124,y:131),.init(x:253,y:121),.init(x:173,y:160),.init(x:219,y:77))
        curve(.init(x:126,y:118),.init(x:253,y:108),.init(x:170,y:144),.init(x:220,y:60))
        line([.init(x:194,y:45),.init(x:216,y:58),.init(x:194,y:71)],close:true,fill:butter)
        glint(234,34)
    }
    private func search() {
        ground(62,182)
        line([.init(x:144,y:90),.init(x:104,y:145)]); line([.init(x:144,y:90),.init(x:188,y:145)]); line([.init(x:144,y:90),.init(x:144,y:148)])
        line([.init(x:80,y:70),.init(x:203,y:27),.init(x:221,y:70),.init(x:93,y:99)],close:true,fill:peach)
        line([.init(x:181,y:35),.init(x:197,y:76)])
        line([.init(x:73,y:73),.init(x:80,y:94),.init(x:94,y:89),.init(x:87,y:68)],close:true,fill:butter)
        oval(202,27,18,44,paper); glint(246,29); glint(241,91)
    }
    private func people() {
        ground()
        for (x,y,color) in [(CGFloat(83),CGFloat(56),pink),(CGFloat(143),CGFloat(34),butter),(CGFloat(202),CGFloat(58),sage)] {
            oval(x-13,y,26,26,color)
            line([.init(x:x-12,y:y+32),.init(x:x-32,y:y+59),.init(x:x-19,y:y+65),.init(x:x-9,y:y+52),.init(x:x-13,y:y+88),.init(x:x,y:y+77),.init(x:x+13,y:y+88),.init(x:x+9,y:y+52),.init(x:x+19,y:y+65),.init(x:x+32,y:y+59),.init(x:x+12,y:y+32)],close:true,fill:color)
        }
    }
    private func saved() {
        ground()
        rect(78,117,137,21,6,peach); rect(72,91,137,23,6,paper); rect(82,64,137,23,6,butter)
        line([.init(x:170,y:60),.init(x:191,y:60),.init(x:191,y:116),.init(x:180,y:105),.init(x:170,y:116)],close:true,fill:pink)
        curve(.init(x:179,y:59),.init(x:179,y:55),.init(x:130,y:23),.init(x:146,y:11))
        curve(.init(x:179,y:58),.init(x:180,y:55),.init(x:220,y:15),.init(x:239,y:39))
        glint(59,54)
    }
    private func notes() {
        ground()
        line([.init(x:64,y:49),.init(x:118,y:34),.init(x:169,y:52),.init(x:222,y:34),.init(x:222,y:128),.init(x:169,y:145),.init(x:118,y:126),.init(x:64,y:142)],close:true,fill:paper)
        line([.init(x:118,y:34),.init(x:118,y:126)]); line([.init(x:169,y:52),.init(x:169,y:145)])
        for y: CGFloat in [64,80,96] { line([.init(x:76,y:y),.init(x:105,y:y-8)]); line([.init(x:132,y:y),.init(x:155,y:y+9)]) }
        line([.init(x:214,y:76),.init(x:243,y:114),.init(x:217,y:149),.init(x:199,y:125)],close:true,fill:peach)
        oval(211,116,7,7,pink); line([.init(x:214,y:122),.init(x:217,y:149)])
    }
    private func audio() {
        ground(77,151)
        curve(.init(x:94,y:105),.init(x:211,y:105),.init(x:72,y:6),.init(x:232,y:6))
        curve(.init(x:105,y:99),.init(x:198,y:99),.init(x:87,y:28),.init(x:216,y:28))
        rect(89,85,30,52,14,pink); rect(190,85,30,52,14,butter)
        curve(.init(x:204,y:137),.init(x:145,y:129),.init(x:217,y:168),.init(x:137,y:156))
        for (x,h) in [(CGFloat(135),CGFloat(15)),(CGFloat(149),CGFloat(32)),(CGFloat(163),CGFloat(23))] { rect(x,100-h/2,5,h,2,peach) }
        glint(241,58)
    }
    private func calendar() {
        ground()
        rect(82,41,138,103,12,paper); rect(82,41,138,27,8,pink)
        for x: CGFloat in [108,192] { rect(x,24,8,31,4,butter) }
        for x: CGFloat in [104,142,180] { for y: CGFloat in [85,114] { rect(x,y,18,10,3,x == 142 && y == 85 ? peach : nil) } }
        glint(55,62)
    }
    private func activity() {
        ground(99,108)
        curve(.init(x:135,y:38),.init(x:164,y:38),.init(x:130,y:14),.init(x:174,y:14))
        // Bell dome is deliberately asymmetric, like a little hand-thrown object.
        var dome = Path(); dome.move(to:.init(x:99,y:121)); dome.addCurve(to:.init(x:149,y:40),control1:.init(x:127,y:109),control2:.init(x:101,y:41)); dome.addCurve(to:.init(x:201,y:121),control1:.init(x:197,y:37),control2:.init(x:171,y:106)); dome.closeSubpath(); shape(dome,fill:butter)
        oval(136,122,26,18,peach); line([.init(x:89,y:121),.init(x:210,y:121)])
        curve(.init(x: 70, y:57),.init(x:79,y:89),.init(x:61,y:69),.init(x:71,y:80))
        glint(225,55)
    }
    private func files() {
        ground()
        rect(91,39,125,91,7,pink); rect(106,26,95,75,4,paper)
        line([.init(x:116,y:47),.init(x:177,y:47)]); line([.init(x:116,y:61),.init(x:168,y:61)])
        line([.init(x:80,y:80),.init(x:213,y:80),.init(x:228,y:137),.init(x:66,y:137)],close:true,fill:butter)
        rect(123,102,49,18,4,paper); line([.init(x:136,y:111),.init(x:159,y:111)])
    }
    private func fitness() {
        ground()
        rect(91,87,124,15,5,paper)
        rect(86,67,20,55,7,pink); rect(69,77,17,34,6,peach)
        rect(202,67,20,55,7,butter); rect(222,77,17,34,6,peach)
        curve(.init(x:117,y:53),.init(x:188,y:36),.init(x:127,y:32),.init(x:151,y:63))
        glint(171,35)
    }
    private func food() {
        ground(70,167)
        oval(101,36,101,101,peach); oval(117,52,69,69,paper)
        curve(.init(x:141,y:86),.init(x:174,y:65),.init(x:118,y:53),.init(x:147,y:49))
        line([.init(x:140,y:90),.init(x:167,y:64)])
        line([.init(x:74,y:45),.init(x:74,y:130)])
        for x: CGFloat in [65,74,83] { line([.init(x:x,y:37),.init(x:x,y:66)]) }
        curve(.init(x:65,y:66),.init(x:83,y:66),.init(x:67,y:77),.init(x:81,y:77))
        line([.init(x:225,y:38),.init(x:211,y:81),.init(x:225,y:81),.init(x:225,y:131)],fill:nil)
    }
    private func shopping() {
        ground()
        curve(.init(x:113,y:79),.init(x:192,y:79),.init(x:104,y:19),.init(x:199,y:19))
        line([.init(x:76,y:78),.init(x:227,y:78),.init(x:206,y:137),.init(x:96,y:137)],close:true,fill:butter)
        for x: CGFloat in [112,139,166,193] { line([.init(x:x,y:89),.init(x:x,y:125)]) }
        line([.init(x:86,y:106),.init(x:216,y:106)])
        oval(102,53,31,29,pink)
        line([.init(x:178,y:74),.init(x:190,y:29),.init(x:204,y:36),.init(x:193,y:78)],close:true,fill:sage)
    }
    private func places() {
        ground()
        rect( 80,66,142,76,3,paper)
        line([.init(x:73,y:68),.init(x:94,y:34),.init(x:209,y:34),.init(x:233,y:68)],close:true,fill:peach)
        for x:CGFloat in [73,105,137,169,201] { rect(x, 60,32,20,9,x == 105 || x == 169 ? paper : pink) }
        rect(103,96,36,46,2,butter); rect(157,94,42,29,3,sage)
    }
    private func safety() {
        ground(103,112)
        var p = Path(); p.addLines([.init(x:150,y:25),.init(x:210,y: 50),.init(x:205,y:92)]); p.addQuadCurve(to:.init(x:150,y:146),control:.init(x:190,y:127)); p.addQuadCurve(to:.init(x:95,y:92),control:.init(x:110,y:127)); p.addLine(to:.init(x:90,y:50)); p.closeSubpath(); shape(p,fill:sage)
        rect(127,76,47,38,8,butter); curve(.init(x:137,y:76),.init(x:164,y:76),.init(x:133,y:44),.init(x:171,y:44))
        oval(147,88,7,7,pink); line([.init(x:150,y:95),.init(x:150,y:102)])
        glint( 60,63)
    }
    private func stickers() {
        ground()
        rect(89,27,127,115,14,paper)
        oval(106,42,45,45,butter); oval(116,55,4,5,peach); oval(135,55,4,5,peach)
        curve(.init(x:117,y:68),.init(x:137,y:68),.init(x:122,y:78),.init(x:132,y:78))
        line([.init(x:172,y:45),.init(x:181,y:59),.init(x:198,y:62),.init(x:185,y:73),.init(x:187,y:89),.init(x:172,y:80),.init(x:159,y:89),.init(x:161,y:72),.init(x:150,y:62),.init(x:166,y:59)],close:true,fill:pink)
        line([.init(x:216,y:107),.init(x:183,y:142),.init(x:183,y:108)],close:true,fill:peach)
        glint( 60,47)
    }
    private func awards() {
        ground()
        rect(106,128,91,15,3,pink); rect(142,94,17,34,3,paper)
        var cup = Path(); cup.move(to:.init(x:115,y:34)); cup.addLine(to:.init(x:190,y:34)); cup.addQuadCurve(to:.init(x:153,y:98),control:.init(x:191,y:97)); cup.addQuadCurve(to:.init(x:115,y:34),control:.init(x:115,y:97)); shape(cup,fill:butter)
        curve(.init(x:115,y:47),.init(x:129,y:81),.init(x: 70,y:27),.init(x:96,y:90))
        curve(.init(x:190,y:47),.init(x:177,y:81),.init(x:229,y:27),.init(x:213,y:90))
        glint(73, 30); glint(232,92)
    }
    private func map() {
        line([.init(x: 60,y:52),.init(x:122,y: 30),.init(x:177,y:51),.init(x:239,y: 30),.init(x:239,y:119),.init(x:177,y:143),.init(x:122,y:122),.init(x: 60,y:143)],close:true,fill:paper)
        line([.init(x:122,y: 30),.init(x:122,y:122)]); line([.init(x:177,y:51),.init(x:177,y:143)])
        curve(.init(x: 70,y:114),.init(x:226,y:77),.init(x:150,y:45),.init(x:123,y:165))
        var pin = Path(); pin.move(to:.init(x:164,y:96)); pin.addCurve(to:.init(x:164,y:42),control1:.init(x:118,y:55),control2:.init(x:141,y:36)); pin.addCurve(to:.init(x:164,y:96),control1:.init(x:200,y:39),control2:.init(x:200,y:57)); shape(pin,fill:pink)
        oval(154,51,20,20,paper)
    }
    private func ideas() {
        ground()
        rect(132,134,86,9,4,pink); line([.init(x:176,y:132),.init(x:197,y: 80),.init(x:152,y:43)])
        line([.init(x:119,y:34),.init(x:156,y:31),.init(x:184,y:69),.init(x:104,y:92)],close:true,fill:butter)
        oval(145, 70,16,11,peach)
        line([.init(x:108,y:104),.init(x:100,y:119)]); line([.init(x:130,y:104),.init(x:130,y:122)])
        rect( 60,127, 50,14,4,paper); glint(238,49)
    }
    private func studio() {
        ground()
        rect(84,66,137,76,5,pink)
        line([.init(x:81,y:61),.init(x:207,y:23),.init(x:214,y: 40),.init(x:88,y:78)],close:true,fill:butter)
        for x: CGFloat in [109,140,171] { line([.init(x:x,y:53-(x-109)*0.3),.init(x:x+13,y:65-(x-109)*0.3)]) }
        line([.init(x:105,y:95),.init(x:197,y:95)]); line([.init(x:105,y:114),.init(x:164,y:114)])
        glint(244,69)
    }
    private func live() {
        ground(103,104)
        rect(132,28,42,72,21,pink)
        curve(.init(x:119,y:72),.init(x:187,y:72),.init(x:117,y:132),.init(x:192,y:130))
        line([.init(x:153,y:117),.init(x:153,y:141)]); rect(120,140,66,5,2,butter)
        for y: CGFloat in [45,58,71] { line([.init(x:143,y:y),.init(x:163,y:y)]) }
        curve(.init(x:97,y:42),.init(x:97,y:96),.init(x: 80,y:55),.init(x: 80,y:83))
        curve(.init(x:210,y:42),.init(x:210,y:96),.init(x:227,y:55),.init(x:227,y:83))
    }
    private func likes() {
        var p = Path(); p.move(to:.init(x:151,y:104)); p.addCurve(to:.init(x:151,y: 40),control1:.init(x:66,y: 50),control2:.init(x:104,y:2)); p.addCurve(to:.init(x:151,y:104),control1:.init(x:198,y:0),control2:.init(x:239,y: 50)); shape(p,fill:pink)
        line([.init(x:151,y:104),.init(x:145,y:114),.init(x:157,y:114)],close:true,fill:peach)
        curve(.init(x:151,y:114),.init(x:129,y:151),.init(x:172,y:145),.init(x:118,y:126))
        glint( 70,85); glint(232, 50)
    }
    private func reposts() {
        rect(80,41,67,88,5,paper); rect(166,59,65, 80,5,pink)
        curve(.init(x:108,y: 30),.init(x:207,y: 40),.init(x:148,y:7),.init(x:190,y:13))
        line([.init(x:193,y: 30),.init(x:207,y: 40),.init(x:209,y:25)])
        curve(.init(x:184,y:148),.init(x:92,y:137),.init(x:147,y:163),.init(x:109,y:157))
        for y: CGFloat in [ 60,76,92] { line([.init(x:94,y:y),.init(x:131,y:y)]) }
        for y: CGFloat in [78,94,110] { line([.init(x:180,y:y),.init(x:214,y:y)]) }
    }
}
