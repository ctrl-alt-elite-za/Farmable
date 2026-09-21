// Every module that talks to the network takes its fetch implementation as an
// argument, so unit tests never reach a real server. Pointing the default at an
// unroutable host makes an accidental real call fail loudly instead of silently
// hitting a developer's machine.
process.env.EXPO_PUBLIC_API_URL = 'http://api.invalid';

// React 19's act() environment check must be told this is a testing environment;
// otherwise state updates inside an async effect (like HealthScreen's fetch) print
// "not configured to support act" and RNTL's `render` never resolves.
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
