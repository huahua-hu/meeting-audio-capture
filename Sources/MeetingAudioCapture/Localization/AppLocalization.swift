import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let defaultLanguage: AppLanguage = .english
    var id: String { rawValue }
}

enum AppTextKey: CaseIterable, Sendable {
    case language
    case english
    case simplifiedChinese
    case ready
    case checkingAudio
    case recording
    case paused
    case saving
    case saved
    case failed
    case systemAudio
    case microphone
    case noSignal
    case systemDefault
    case saveTo
    case choose
    case openPrivacySettings
    case openFolder
    case consentNotice
    case refreshMicrophones
    case quit
    case startRecording
    case waitingForTracks
    case pause
    case stop
    case resume
    case savingFiles
    case permissionDenied
    case noDisplay
    case captureSetupFormat
    case insufficientSpace
    case exportFailed
    case unexpectedCaptureStop
    case genericErrorFormat
}

enum AppLocalizer {
    static func text(_ key: AppTextKey, language: AppLanguage) -> String {
        translations[language]?[key] ?? translations[.english]?[key] ?? ""
    }

    static func format(_ key: AppTextKey, language: AppLanguage, _ arguments: CVarArg...) -> String {
        let format = text(key, language: language)
        let locale = language == .simplifiedChinese
            ? Locale(identifier: "zh_CN")
            : Locale(identifier: "en_US")
        return String(format: format, locale: locale, arguments: arguments)
    }

    private static let translations: [AppLanguage: [AppTextKey: String]] = [
        .english: [
            .language: "Language",
            .english: "English",
            .simplifiedChinese: "Simplified Chinese",
            .ready: "Ready",
            .checkingAudio: "Checking audio…",
            .recording: "Recording",
            .paused: "Paused",
            .saving: "Saving…",
            .saved: "Saved",
            .failed: "Failed",
            .systemAudio: "System Audio",
            .microphone: "Microphone",
            .noSignal: "No signal",
            .systemDefault: "System Default",
            .saveTo: "Save to",
            .choose: "Choose…",
            .openPrivacySettings: "Open Privacy Settings",
            .openFolder: "Open Folder",
            .consentNotice: "Record only with required consent and in accordance with applicable laws and meeting policies.",
            .refreshMicrophones: "Refresh Microphones",
            .quit: "Quit",
            .startRecording: "Start Recording",
            .waitingForTracks: "Waiting for both audio tracks…",
            .pause: "Pause",
            .stop: "Stop",
            .resume: "Resume",
            .savingFiles: "Saving files…",
            .permissionDenied: "Recording permission was denied. Enable MeetingAudioCapture in System Settings > Privacy & Security > Microphone and Screen & System Audio Recording.",
            .noDisplay: "No display is available for system audio capture.",
            .captureSetupFormat: "Unable to start audio capture: %@",
            .insufficientSpace: "At least 500 MB of free space is required.",
            .exportFailed: "One or more audio exports failed.",
            .unexpectedCaptureStop: "Audio capture stopped unexpectedly.",
            .genericErrorFormat: "Error: %@"
        ],
        .simplifiedChinese: [
            .language: "语言",
            .english: "English",
            .simplifiedChinese: "简体中文",
            .ready: "就绪",
            .checkingAudio: "正在检查音频…",
            .recording: "录音中",
            .paused: "已暂停",
            .saving: "正在保存…",
            .saved: "已保存",
            .failed: "失败",
            .systemAudio: "系统声音",
            .microphone: "麦克风",
            .noSignal: "无信号",
            .systemDefault: "系统默认",
            .saveTo: "保存到",
            .choose: "选择…",
            .openPrivacySettings: "打开隐私设置",
            .openFolder: "打开文件夹",
            .consentNotice: "请仅在取得必要同意并遵守适用法律及会议规则的情况下录音。",
            .refreshMicrophones: "刷新麦克风列表",
            .quit: "退出",
            .startRecording: "开始录音",
            .waitingForTracks: "正在等待两路音频…",
            .pause: "暂停",
            .stop: "停止",
            .resume: "继续",
            .savingFiles: "正在保存文件…",
            .permissionDenied: "录音权限被拒绝。请在“系统设置 > 隐私与安全性”中为 MeetingAudioCapture 开启“麦克风”和“录屏与系统录音”权限。",
            .noDisplay: "没有可用于捕获系统声音的显示器。",
            .captureSetupFormat: "无法启动音频捕获：%@",
            .insufficientSpace: "至少需要 500 MB 可用空间。",
            .exportFailed: "一个或多个音频文件导出失败。",
            .unexpectedCaptureStop: "音频捕获意外停止。",
            .genericErrorFormat: "错误：%@"
        ]
    ]
}
