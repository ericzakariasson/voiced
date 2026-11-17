import Foundation

/// Output and a time limit for a check that runs as a process of its own, as the microphone
/// check does, where a person may be waiting on it from another Mac.
public enum StandaloneCheck {
    /// Writes one line to standard output in a single unbuffered write, so the line is in the
    /// file even if the process is ended from outside the next moment. `print` keeps what it
    /// writes to a file until the process exits in an orderly way.
    public static func say(_ line: String) {
        let bytes = Array((line + "\n").utf8)
        bytes.withUnsafeBufferPointer { buffer in
            _ = write(STDOUT_FILENO, buffer.baseAddress, buffer.count)
        }
    }

    /// Ends the process `limit` from now, whatever its other threads are doing.
    ///
    /// The wait is on a thread of its own, which depends on no dispatch queue, so a main queue or
    /// an audio queue that is stuck cannot hold it up. It writes `lines` and ends with `_exit`,
    /// which runs nothing on the way out that a stuck thread could block.
    public static func endProcess(after limit: Duration, code: Int32, saying lines: [String]) {
        let seconds = Double(limit / .milliseconds(1)) / 1000
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: seconds)
            for line in lines {
                say(line)
            }
            _exit(code)
        }
    }
}
