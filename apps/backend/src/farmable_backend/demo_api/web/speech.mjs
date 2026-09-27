// Browser speech only: no Azure/Gemini credentials, wake words or automatic plan approval.
export class SpeechController {
  constructor({ env = globalThis, onState, onTranscript, onError }) {
    this.env = env;
    this.onState = onState;
    this.onTranscript = onTranscript;
    this.onError = onError;
    this.epoch = 0;
    this.state = 'idle';
    this.recognition = null;
    this.timer = null;
  }

  supported() {
    return Boolean(this.env.SpeechRecognition || this.env.webkitSpeechRecognition);
  }

  setState(state) {
    this.state = state;
    this.onState(state);
  }

  stop() {
    this.epoch += 1;
    this.env.clearTimeout(this.timer);
    this.timer = null;
    const previous = this.recognition;
    this.recognition = null;
    try {
      previous?.abort();
    } catch {
      // Already ended; callbacks are invalidated regardless.
    }
    this.env.speechSynthesis?.cancel();
    this.setState('idle');
  }

  listen(consented) {
    // Cancel speech BEFORE starting the mic so the app does not transcribe its own reply.
    this.stop();
    if (!consented) {
      this.onError('Enable browser speech consent first, or type your message.');
      return;
    }
    const Recognition = this.env.SpeechRecognition || this.env.webkitSpeechRecognition;
    if (!Recognition || !this.env.isSecureContext) {
      this.onError('Voice is unavailable here. Use localhost in a supported browser, or type.');
      return;
    }
    const epoch = this.epoch;
    const recognition = new Recognition();
    this.recognition = recognition;
    recognition.lang = 'en-ZA';
    recognition.continuous = false;
    recognition.interimResults = true;
    recognition.maxAlternatives = 1;
    let finalSeen = false;
    recognition.onresult = (event) => {
      if (epoch !== this.epoch || finalSeen) return;
      const final = [];
      const interim = [];
      for (let index = event.resultIndex; index < event.results.length; index += 1) {
        const result = event.results[index];
        (result.isFinal ? final : interim).push(result[0].transcript);
      }
      if (final.length) {
        finalSeen = true;
        const transcript = final.join(' ').trim();
        this.stop();
        if (!transcript || transcript.length > 300) {
          this.onError('No short transcript was recognised. Try again or type.');
        } else {
          this.onTranscript(transcript, true);
        }
      } else if (interim.length) {
        this.onTranscript(interim.join(' ').slice(0, 300), false);
      }
    };
    recognition.onerror = () => {
      if (epoch !== this.epoch) return;
      this.stop();
      this.onError('Voice is unavailable right now. Check mic permission/internet, or type.');
    };
    recognition.onend = () => {
      if (epoch !== this.epoch) return;
      this.stop();
      if (!finalSeen) this.onError('No final speech result. Try again or type.');
    };
    this.setState('listening');
    this.timer = this.env.setTimeout(() => {
      if (epoch !== this.epoch) return;
      this.stop();
      this.onError('Listening timed out after 15 seconds. Try again or type.');
    }, 15000);
    try {
      recognition.start();
    } catch {
      if (epoch !== this.epoch) return;
      this.stop();
      this.onError('The microphone could not start. Try again or type.');
    }
  }

  speak(text, consented) {
    this.stop();
    if (!consented) {
      this.onError('Browser speech consent is off; the reply remains available as text.');
      return;
    }
    if (!this.env.speechSynthesis || !this.env.SpeechSynthesisUtterance) {
      this.onError('Spoken replies are unavailable; read the reply instead.');
      return;
    }
    const epoch = this.epoch;
    const utterance = new this.env.SpeechSynthesisUtterance(text);
    utterance.lang = 'en-ZA';
    const voices = this.env.speechSynthesis.getVoices();
    utterance.voice =
      voices.find((voice) => voice.localService && voice.lang === 'en-ZA') ||
      voices.find((voice) => voice.localService && voice.lang.startsWith('en')) ||
      voices.find((voice) => voice.lang.startsWith('en')) ||
      null;
    const finish = () => {
      if (epoch !== this.epoch) return;
      this.stop();
    };
    utterance.onend = finish;
    utterance.onerror = () => {
      if (epoch !== this.epoch) return;
      finish();
      this.onError('Spoken reply failed; the text is still available.');
    };
    this.setState('speaking');
    this.timer = this.env.setTimeout(finish, 30000);
    try {
      this.env.speechSynthesis.speak(utterance);
    } catch {
      utterance.onerror();
    }
  }
}
