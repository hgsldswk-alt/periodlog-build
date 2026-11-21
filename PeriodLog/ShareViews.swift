import SwiftUI
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins

struct ActivityItem: Identifiable { let id = UUID(); var items: [Any] }
struct ActivitySheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}
enum CardRenderer {
    @MainActor static func image<V: View>(_ view: V) -> UIImage? {
        let content = view.frame(width: 360, height: 450).environment(\.colorScheme, .light).dynamicTypeSize(.large)
        let renderer = ImageRenderer(content: content); renderer.scale = 3; renderer.isOpaque = true
        return renderer.uiImage
    }
    static func qr(_ url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(url.absoluteString.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage, let image = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) else { return nil }
        return UIImage(cgImage: image)
    }
}
struct ShareCardView: View {
    var payload: ShareCode.Payload
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L.t("经期提醒卡")).font(.system(size: 12, weight: .medium)).tracking(2).foregroundStyle(Design.primary)
            Spacer(minLength: 0)
            Text(payload.nickname.map { L.f("%@ 的下次经期大约在", $0) } ?? L.t("下次经期大约在")).font(.system(size: 23, weight: .semibold)).foregroundStyle(Design.ink).fixedSize(horizontal: false, vertical: true)
            if let f = payload.predictions.first {
                Text(L.range(f.rangeStart, f.rangeEnd)).font(.system(size: 29, weight: .semibold, design: .rounded)).foregroundStyle(Design.primary).minimumScaleFactor(0.65).lineLimit(2)
                if let duration = f.duration { Text(L.f("大约持续 %@ 天", String(duration))).font(.system(size: 13)).foregroundStyle(Design.secondary) }
            }
            Text(L.t(payload.kind == .partner && payload.partnerTips ? "这几天可能比较累，多一点耐心。" : "到时候我们互相提醒一下")).font(.system(size: 13)).foregroundStyle(Design.secondary)
            Spacer(minLength: 0)
            cardFooter
        }.padding(26).frame(width: 360, height: 450).background(Design.background)
    }
    private var cardFooter: some View {
        VStack(spacing: 16) {
            Rectangle().fill(Design.line).frame(height: 1)
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L.t("隐私经期记录")).font(.system(size: 14, weight: .semibold)).foregroundStyle(Design.ink)
                    Text(L.t("不用注册 · 没有广告 · 数据只在手机里")).font(.system(size: 11)).foregroundStyle(Design.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let url = ShareText.storeURL, let qr = CardRenderer.qr(url) { Image(uiImage: qr).interpolation(.none).resizable().frame(width: 58, height: 58).padding(3).background(Color.white) }
            }
        }
    }
}
struct CardPreview: View {
    let image: UIImage?
    var body: some View {
        if let image = image {
            Image(uiImage: image).resizable().aspectRatio(0.8, contentMode: .fit).frame(maxWidth: 360).clipShape(RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(Design.line, lineWidth: 1)).accessibilityIdentifier("shareCardPreview")
        }
    }
}
struct ShareSheetView: View {
    let kind: ShareKind
    @EnvironmentObject private var model: AppModel
    @State private var includeName = true
    @State private var includeDuration = false
    @State private var tips = true
    @State private var saveImage = false
    @State private var activity: ActivityItem?
    @State private var document = ExportDocument(Data())
    private var payload: ShareCode.Payload? { try? model.makePayload(kind: kind, name: includeName, duration: includeDuration, tips: tips) }
    private var image: UIImage? { payload.flatMap { CardRenderer.image(ShareCardView(payload: $0)) } }
    var body: some View {
        SheetFrame(title: L.t(kind == .friend ? "和闺蜜一起记" : "给伴侣")) {
            ScrollView {
                VStack(spacing: 16) {
                    Text(L.t("对方添加口令后，可以在自己的手机上开启提醒。不经过任何服务器。")) .font(.caption).foregroundStyle(Design.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    if payload != nil {
                        CardPreview(image: image)
                        Toggle(L.t("下次经期大约哪几天（必选）"), isOn: .constant(true)).disabled(true).accessibilityIdentifier("shareRequiredRange")
                        Toggle(L.t("我的昵称"), isOn: $includeName).accessibilityIdentifier("shareIncludeName")
                        if includeName { TextField(L.t("昵称（可留空）"), text: model.setting(\.nickname)).textFieldStyle(.roundedBorder).accessibilityIdentifier("shareNickname") }
                        Toggle(L.t("经期大约持续几天"), isOn: $includeDuration).accessibilityIdentifier("shareIncludeDuration")
                        if kind == .partner { Toggle(L.t("这几天的小提示"), isOn: $tips).accessibilityIdentifier("sharePartnerTips") }
                        Text(L.t("口令永远不包含历史记录、易孕期、症状或体温。")) .font(.caption).foregroundStyle(Design.secondary)
                        HStack(spacing: 10) {
                            Button(L.t("保存图片")) { if let image = image { activity = ActivityItem(items: [image]) } }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("saveShareImage")
                            Button(L.t("复制口令")) { copyCode() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("copyShareCode")
                        }
                        Button(L.t("系统分享")) {
                            guard let p = payload, let code = try? ShareCode.encode(p), let image = image else { return }
                            activity = ActivityItem(items: [image, ShareText.code(code)])
                        }.accessibilityIdentifier("systemShareCode")
                    } else {
                        Text(L.t("先记一次经期，得到预测后就可以生成口令。暂停预测时不生成口令。")) .padding(.vertical, 40)
                    }
                }.padding(20)
            }
        }.fileExporter(isPresented: $saveImage, document: document, contentType: .png, defaultFilename: "PeriodLog-card") { result in
            if case .failure = result { model.message = L.t("图片未保存，你可以重新选择保存位置。") }
        }.sheet(item: $activity) { ActivitySheet(items: $0.items) }
    }
    private func copyCode() {
        guard let p = payload else { return }
        do { UIPasteboard.general.string = ShareText.code(try ShareCode.encode(p)); model.message = L.t("口令已复制，可以发给对方。") }
        catch { model.message = L.t("暂时无法生成口令，请稍后重试。") }
    }
}
struct InvitationArtwork: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L.t("给朋友的一张卡片")).font(.system(size: 12)).tracking(2).foregroundStyle(Design.primary)
            Spacer(minLength: 0)
            Text(L.t("我在用的经期记录，不用注册，也没有广告")).font(.system(size: 29, weight: .semibold)).foregroundStyle(Design.ink).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("数据只在手机")); Text(L.t("可以和朋友互相提醒")); Text(L.t("一次买断"))
            }.font(.system(size: 15)).foregroundStyle(Design.secondary)
            Spacer(minLength: 0)
            HStack {
                Text(L.t("隐私经期记录")).font(.system(size: 17, weight: .semibold)).foregroundStyle(Design.primary)
                Spacer()
                if let url = ShareText.storeURL, let qr = CardRenderer.qr(url) { Image(uiImage: qr).interpolation(.none).resizable().frame(width: 60, height: 60).padding(4).background(Color.white) }
            }
        }.padding(28).frame(width: 360, height: 450).background(Design.background)
    }
}
struct InviteCardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var activity: ActivityItem?
    @State private var saveImage = false
    private var image: UIImage? { CardRenderer.image(InvitationArtwork()) }
    var body: some View {
        SheetFrame(title: L.t("推荐给朋友")) {
            ScrollView {
                VStack(spacing: 20) {
                    CardPreview(image: image)
                    Text(L.t("这张邀请卡不含任何个人数据。")) .font(.caption).foregroundStyle(Design.secondary)
                    Button(L.t("保存图片")) { if let image = image { activity = ActivityItem(items: [image]) } }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("saveInviteImage")
                    Button(L.t("复制推荐文案")) { UIPasteboard.general.string = ShareText.invitation; model.message = L.t("文案已复制。") }.accessibilityIdentifier("copyInviteText")
                    Button(L.t("系统分享")) { if let image = image { activity = ActivityItem(items: [image, ShareText.invitation]) } }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("shareInvite")
                }.padding(20)
            }
        }.fileExporter(isPresented: $saveImage, document: ExportDocument(image?.pngData() ?? Data()), contentType: .png, defaultFilename: "PeriodLog-invite") { _ in }
            .sheet(item: $activity) { ActivitySheet(items: $0.items) }
    }
}
struct MilestoneArtwork: View {
    let count: Int
    let date: Day
    let average: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L.t("给坚持记录的自己")).font(.system(size: 13)).foregroundStyle(Design.secondary)
            Spacer()
            Text(String(count)).font(.system(size: 100, weight: .semibold, design: .rounded)).foregroundStyle(Design.primary)
            Text(L.f("连续记录 %@ 个周期", String(count))).font(.system(size: 26, weight: .semibold)).foregroundStyle(Design.ink)
            Text(L.day(date)).font(.system(size: 15)).foregroundStyle(Design.secondary)
            if let average = average { Text(L.f("平均周期 %@ 天", String(format: "%.1f", average))).font(.system(size: 14)).foregroundStyle(Design.secondary) }
            Spacer()
            Text(L.t("隐私经期记录")).font(.system(size: 15, weight: .medium)).foregroundStyle(Design.primary)
        }.padding(30).frame(width: 360, height: 450).background(Design.background)
    }
}
struct MilestoneCardView: View {
    let count: Int
    @EnvironmentObject private var model: AppModel
    @State private var includeAverage = false
    @State private var saveImage = false
    @State private var activity: ActivityItem?
    private var image: UIImage? { CardRenderer.image(MilestoneArtwork(count: count, date: model.today, average: includeAverage ? CycleCore.statistics(logs: model.data.logs).averageCycle : nil)) }
    var body: some View {
        SheetFrame(title: L.t("记录里程碑")) {
            ScrollView {
                VStack(spacing: 20) {
                    CardPreview(image: image)
                    Toggle(L.t("加上平均周期天数"), isOn: $includeAverage).accessibilityIdentifier("milestoneIncludeAverage")
                    Button(L.t("保存图片")) { if let image = image { activity = ActivityItem(items: [image]) } }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("saveMilestone")
                    Button(L.t("系统分享")) { if let image = image { activity = ActivityItem(items: [image, ShareText.invitation]) } }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("shareMilestone")
                    Button(L.t("推荐给朋友")) { model.page = .invite }.accessibilityIdentifier("milestoneInvite")
                }.padding(20)
            }
        }.fileExporter(isPresented: $saveImage, document: ExportDocument(image?.pngData() ?? Data()), contentType: .png, defaultFilename: "PeriodLog-milestone") { _ in }
            .sheet(item: $activity) { ActivitySheet(items: $0.items) }
    }
}
