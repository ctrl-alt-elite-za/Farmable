/* global API_URL, EMAIL, PASSWORD, SECTION, http, json, output */
// Maestro runs this with its own JavaScript runtime: `http`, `json` and
// `output` are Maestro globals, and the upper-case names are the flow env.
// Runs on the host, against this stack's API (API_URL): logs in as the
// flow's account and gives its farm one section, the way a second phone or
// the web would. The app has no "new section" screen yet, and an observation
// needs a section the server knows.
function uuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
    var r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}
var json_headers = { 'Content-Type': 'application/json' };
var login = http.post(API_URL + '/auth/login', {
  headers: json_headers,
  body: JSON.stringify({ identifier: EMAIL, password: PASSWORD }),
});
if (login.status !== 200) throw new Error('login returned ' + login.status);
var auth = {
  Authorization: 'Bearer ' + json(login.body).access_token,
  'Content-Type': 'application/json',
};
var farms = json(http.get(API_URL + '/farms', { headers: auth }).body).items;
if (farms.length !== 1) throw new Error('expected one farm, found ' + farms.length);
var created = http.post(API_URL + '/farms/' + farms[0].id + '/sections', {
  headers: auth,
  body: JSON.stringify({ id: uuid(), mutation_id: uuid(), name: SECTION }),
});
if (created.status !== 200) throw new Error('section returned ' + created.status);
output.farmId = farms[0].id;
