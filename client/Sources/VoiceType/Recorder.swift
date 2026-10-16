import AVFoundation

/// 錄麥克風，即時轉成 16kHz 單聲道 16-bit，結束時包成 WAV。
/// USB 麥克風（例如 Studio Display）冷啟動要幾百毫秒，所以錄完後讓引擎再跑 20 秒，
/// 連續講話時第二句以後就不用再等。
final class Recorder {
    /// 開始錄音後第一段音訊真的進來時呼叫（主執行緒），可以在這時提示使用者開口
    var onFirstAudio: ((TimeInterval) -> Void)?

    private let engine = AVAudioEngine()
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                       channels: 1, interleaved: true)!
    private var pcm = Data()
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var startedAt = Date()
    private var gotFirstAudio = false
    private var idleStop: DispatchWorkItem?
    private let warmSeconds: TimeInterval = 20  // 太長的話選單列的麥克風指示燈會一直亮著

    private(set) var isRecording = false
    /// 最近一段音訊的音量（0～1），給提示條畫音量
    private(set) var level: Float = 0

    func start() throws {
        idleStop?.cancel()
        lock.lock(); pcm.removeAll(); gotFirstAudio = false; lock.unlock()
        startedAt = Date()
        if !engine.isRunning {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard let conv = AVAudioConverter(from: format, to: target) else {
                throw NSError(domain: "VoiceType", code: 1, userInfo: [NSLocalizedDescriptionKey: "無法建立音訊轉換器"])
            }
            converter = conv
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.append(buffer)
            }
            engine.prepare()
            try engine.start()
        }
        isRecording = true
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard isRecording, let converter else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let ch = out.int16ChannelData else { return }
        let n = Int(out.frameLength)
        var sum: Float = 0
        for i in 0..<n { let v = Float(ch[0][i]) / 32768; sum += v * v }
        level = n > 0 ? min(1, sqrt(sum / Float(n)) * 8) : 0
        let bytes = Data(bytes: ch[0], count: n * 2)
        lock.lock()
        pcm.append(bytes)
        let first = !gotFirstAudio
        gotFirstAudio = true
        lock.unlock()
        if first {
            let latency = Date().timeIntervalSince(startedAt)
            DispatchQueue.main.async { self.onFirstAudio?(latency) }
        }
    }

    /// 停止錄音，回傳 (WAV 資料, 秒數)；引擎保溫一段時間後才真的關麥克風
    func stop() -> (Data, Double) {
        isRecording = false
        level = 0
        lock.lock(); let data = pcm; lock.unlock()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isRecording else { return }
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
        }
        idleStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + warmSeconds, execute: work)
        return (Recorder.wav(data), Double(data.count) / 2 / 16000)
    }

    private static func wav(_ pcm: Data) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + pcm.count))
        d.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
        u32(16000); u32(32000); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(pcm.count))
        d.append(pcm)
        return d
    }
}
