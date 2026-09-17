// Every module that talks to the network takes its fetch implementation as an
// argument, so unit tests never reach a real server. Pointing the default at an
// unroutable host makes an accidental real call fail loudly instead of silently
// hitting a developer's machine.
process.env.EXPO_PUBLIC_API_URL = 'http://api.invalid';
