// Runs on the host after the phone reports the record sent: the server must
// hold exactly one media record, and exactly one observation pointing at it.
var login = http.post(API_URL + '/auth/login', {
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ identifier: EMAIL, password: PASSWORD }),
});
if (login.status !== 200) throw new Error('login returned ' + login.status);
var auth = { Authorization: 'Bearer ' + json(login.body).access_token };
var farm = json(http.get(API_URL + '/farms', { headers: auth }).body).items[0];
var base = API_URL + '/farms/' + farm.id;
var media = json(http.get(base + '/media', { headers: auth }).body).items;
var observations = json(
  http.get(base + '/observations', { headers: auth }).body,
).items;
if (media.length !== 1) throw new Error('expected 1 media record, found ' + media.length);
if (observations.length !== 1) {
  throw new Error('expected 1 observation, found ' + observations.length);
}
if (observations[0].media_id !== media[0].id) {
  throw new Error('the observation does not carry the uploaded photo');
}
output.mediaCount = media.length;
