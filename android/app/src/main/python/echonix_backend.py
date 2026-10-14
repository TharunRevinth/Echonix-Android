import os
import sys
import json
import time
import urllib.request
import urllib.parse
import re
import threading
import shlex
import yt_dlp
from ytmusicapi import YTMusic

ytm = None
creds_file_path = None
ytm_cache_path = None
_ytm_lock = threading.Lock()

def init_ytmusic(creds_dir):
    global ytm, creds_file_path, ytm_cache_path
    with _ytm_lock:
        ytm_cache_path = creds_dir
        creds_file_path = os.path.join(creds_dir, 'browser.json')
        try:
            if os.path.exists(creds_file_path):
                ytm = YTMusic(creds_file_path)
            else:
                ytm = YTMusic()
        except Exception as e:
            try:
                ytm = YTMusic()
            except Exception:
                ytm = None

_auth_status_cache = {'time': 0, 'result': None}

def parse_curl_command(curl_cmd):
    headers = {}
    clean_cmd = re.sub(r'\^[\r\n]+', ' ', curl_cmd)
    clean_cmd = re.sub(r'\\(?:[\r\n]+)', ' ', clean_cmd)
    clean_cmd = clean_cmd.replace('`\n', ' ').replace('`\r\n', ' ')

    try:
        tokens = shlex.split(clean_cmd)
        i = 0
        while i < len(tokens):
            tok = tokens[i]
            if tok in ('-H', '--header') and i + 1 < len(tokens):
                header_line = tokens[i + 1]
                if ':' in header_line:
                    k, v = header_line.split(':', 1)
                    headers[k.strip().lower()] = v.strip()
                i += 2
            elif tok in ('-b', '--cookie') and i + 1 < len(tokens):
                headers['cookie'] = tokens[i + 1].strip()
                i += 2
            else:
                i += 1
    except Exception:
        pass

    if not headers.get('cookie'):
        header_matches = re.findall(r'(?:-H|--header)\s+["\']?([^:\r\n]+):\s*([^"\']+)["\']?', clean_cmd, re.IGNORECASE)
        for key, val in header_matches:
            headers[key.strip().lower()] = val.strip()
        cookie_matches = re.findall(r'(?:-b|--cookie)\s+["\']?([^"\']+)["\']?', clean_cmd, re.IGNORECASE)
        if cookie_matches:
            headers['cookie'] = cookie_matches[0].strip()

    return headers

def login_with_cookie(cookie_str_or_curl, creds_dir):
    global ytm, creds_file_path, ytm_cache_path, _auth_status_cache
    ytm_cache_path = creds_dir
    creds_file_path = os.path.join(creds_dir, 'browser.json')
    tmp_creds_path = os.path.join(creds_dir, 'browser.json.tmp')

    try:
        d = cookie_str_or_curl.strip()
        headers = {}
        cookie_val = ''

        if any(token in d for token in ('curl', '-H', '--header', '-b', '--cookie')):
            headers = parse_curl_command(d)
            cookie_val = headers.get('cookie', '')

        if not cookie_val:
            cookie_match = re.search(r'^\s*cookie:\s*(.+)$', d, re.IGNORECASE | re.MULTILINE)
            if cookie_match:
                cookie_val = cookie_match.group(1).strip()
            elif '=' in d:
                cookie_val = d

        if not cookie_val:
            return json.dumps({"success": False, "error": "No Cookie found in the pasted content."})

        # Validate cookie contains at least one of SAPISID, __Secure-3PAPISID, SID
        has_sapisid = 'SAPISID' in cookie_val
        has_sec_sapisid = '__Secure-3PAPISID' in cookie_val
        has_sid = 'SID=' in cookie_val

        if not (has_sapisid or has_sec_sapisid or has_sid):
            return json.dumps({"success": False, "error": "missing required auth cookies (need SAPISID or SID)"})

        # Ensure __Secure-3PAPISID is present for ytmusicapi compatibility
        if not has_sec_sapisid and has_sapisid:
            sapisid_match = re.search(r'SAPISID=([^;]+)', cookie_val)
            if sapisid_match:
                cookie_val = cookie_val.rstrip('; ') + f"; __Secure-3PAPISID={sapisid_match.group(1).strip()}"

        sapisid_target = ''
        sec_match = re.search(r'__Secure-3PAPISID=([^;]+)', cookie_val)
        if sec_match:
            sapisid_target = sec_match.group(1).strip()
        else:
            sapisid_match = re.search(r'SAPISID=([^;]+)', cookie_val)
            if sapisid_match:
                sapisid_target = sapisid_match.group(1).strip()

        auth_val = headers.get('authorization', '')
        if (not auth_val or 'SAPISIDHASH' not in auth_val) and sapisid_target:
            import hashlib
            import time
            sha_1 = hashlib.sha1()
            unix_timestamp = str(int(time.time()))
            sha_1.update((unix_timestamp + " " + sapisid_target + " https://music.youtube.com").encode("utf-8"))
            auth_val = "SAPISIDHASH " + unix_timestamp + "_" + sha_1.hexdigest()

        final_headers = {
            'User-Agent': headers.get('user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36'),
            'Accept': headers.get('accept', '*/*'),
            'Accept-Language': headers.get('accept-language', 'en-US,en;q=0.9'),
            'Content-Type': 'application/json',
            'x-goog-authuser': headers.get('x-goog-authuser', '0'),
            'x-origin': 'https://music.youtube.com',
            'Cookie': cookie_val
        }
        if auth_val:
            final_headers['Authorization'] = auth_val

        # Write to temporary file first
        os.makedirs(creds_dir, exist_ok=True)
        with open(tmp_creds_path, 'w', encoding='utf-8') as f:
            json.dump(final_headers, f, indent=2)

        # Test temporary credentials
        test_ytm = YTMusic(tmp_creds_path)
        test_ytm.get_library_songs(limit=1)

        # On success, atomically replace final credentials
        os.replace(tmp_creds_path, creds_file_path)
        with _ytm_lock:
            ytm = test_ytm
        _auth_status_cache = {'time': time.time(), 'result': {"authenticated": True, "valid": True}}
        return json.dumps({"success": True})

    except Exception as auth_e:
        # Remove tmp file only; preserve existing browser.json if any
        try:
            if os.path.exists(tmp_creds_path):
                os.remove(tmp_creds_path)
        except:
            pass
        return json.dumps({"success": False, "error": f"Authentication test failed: {str(auth_e)}"})

def logout():
    global ytm, creds_file_path, _auth_status_cache
    try:
        if creds_file_path and os.path.exists(creds_file_path):
            os.remove(creds_file_path)
        with _ytm_lock:
            ytm = YTMusic()
        _auth_status_cache = {'time': time.time(), 'result': {"authenticated": False, "valid": False}}
        return json.dumps({"success": True})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

def check_auth_status():
    global creds_file_path, ytm, _auth_status_cache
    now = time.time()
    if _auth_status_cache.get('result') is not None and (now - _auth_status_cache.get('time', 0)) < 600:
        return json.dumps(_auth_status_cache['result'])

    has_creds = os.path.exists(creds_file_path) if creds_file_path else False
    if not has_creds:
        res = {"authenticated": False, "valid": False}
        _auth_status_cache = {'time': now, 'result': res}
        return json.dumps(res)

    try:
        if not ytm and creds_file_path:
            with _ytm_lock:
                ytm = YTMusic(creds_file_path)
        if ytm:
            ytm.get_library_songs(limit=1)
            res = {"authenticated": True, "valid": True}
        else:
            res = {"authenticated": True, "valid": False}
    except Exception:
        res = {"authenticated": True, "valid": False}

    _auth_status_cache = {'time': now, 'result': res}
    return json.dumps(res)

def get_home_feed():
    global ytm
    if not ytm:
        return json.dumps({"success": False, "error": "YTMusic not initialized"})
    try:
        sections = ytm.get_home(limit=10)
        parsed_sections = []
        for sec in sections:
            if not isinstance(sec, dict):
                continue
            title = sec.get('title', '')
            contents = sec.get('contents', [])
            if not title or not contents:
                continue

            is_song_section = any('videoId' in item for item in contents if isinstance(item, dict))

            parsed_contents = []
            for item in contents:
                if not isinstance(item, dict):
                    continue

                vid = item.get('videoId')
                playlist_id = item.get('playlistId')
                browse_id = item.get('browseId')

                thumb = (item.get('thumbnails') or [{}])[-1].get('url', '')
                artists = ', '.join(a['name'] for a in item.get('artists', [])) if item.get('artists') else ''
                if not artists and item.get('description'):
                    artists = item.get('description')

                parsed_item = {
                    "title": item.get('title', ''),
                    "thumbnail": thumb,
                    "artists": artists,
                    "id": vid or playlist_id or browse_id or "",
                    "type": "song" if vid else "playlist" if playlist_id else "album" if browse_id else "unknown"
                }
                parsed_contents.append(parsed_item)

            parsed_sections.append({
                "title": title,
                "isSongSection": is_song_section,
                "contents": parsed_contents
            })
        return json.dumps({"success": True, "sections": parsed_sections})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

def search_songs(query):
    global ytm
    try:
        results = []
        # Try to search with filter='songs' (YouTube Music official tracks) first
        try:
            if ytm:
                results = ytm.search(query, filter='songs', limit=30)
            else:
                results = YTMusic().search(query, filter='songs', limit=30)
        except Exception:
            pass

        # If no songs are found or search failed, fall back to general search (songs + videos mix)
        if not results:
            try:
                if ytm:
                    results = ytm.search(query, limit=30)
                else:
                    results = YTMusic().search(query, limit=30)
            except Exception:
                results = []

        songs = []
        for r in results:
            vid = r.get('videoId')
            if vid:
                title = r.get('title', '')
                artist = ', '.join(a['name'] for a in r.get('artists', [])) or 'Unknown'
                duration = r.get('duration_seconds', 0)
                
                # Apply filterMusicResults logic from Echonix client:
                title_lower = title.lower()
                # 1. Filter out vlogs, podcasts, tutorials
                if any(k in title_lower for k in ['vlog', 'podcast', 'tutorial']):
                    continue
                # 2. Filter out items where duration is too long (over 9 minutes) or too short (under 45s)
                if duration > 0 and (duration > 540 or duration < 45):
                    continue

                songs.append({
                    'id': vid,
                    'title': title,
                    'artist': artist,
                    'album': r.get('album', {}).get('name', '') if r.get('album') else '',
                    'thumbnail': (r.get('thumbnails') or [{}])[-1].get('url', ''),
                    'duration': duration
                })
        return json.dumps({"success": True, "songs": songs})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

def get_playlist_details(playlist_id):
    global ytm
    if not ytm:
        return json.dumps({"success": False, "error": "YTMusic not initialized"})
    try:
        res = ytm.get_playlist(playlist_id, limit=100)
        tracks = []
        for r in res.get('tracks', []):
            vid = r.get('videoId')
            if vid:
                tracks.append({
                    'id': vid,
                    'title': r.get('title', ''),
                    'artist': ', '.join(a['name'] for a in r.get('artists', [])) or 'Unknown',
                    'album': r.get('album', {}).get('name', '') if r.get('album') else '',
                    'thumbnail': (r.get('thumbnails') or [{}])[-1].get('url', ''),
                    'duration': r.get('duration_seconds', 0)
                })
        return json.dumps({
            "success": True,
            "title": res.get('title', ''),
            "description": res.get('description', ''),
            "thumbnail": (res.get('thumbnails') or [{}])[-1].get('url', ''),
            "tracks": tracks
        })
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

def get_album_details(album_id):
    global ytm
    if not ytm:
        return json.dumps({"success": False, "error": "YTMusic not initialized"})
    try:
        res = ytm.get_album(album_id)
        tracks = []
        for r in res.get('tracks', []):
            vid = r.get('videoId')
            if vid:
                tracks.append({
                    'id': vid,
                    'title': r.get('title', ''),
                    'artist': ', '.join(a['name'] for a in r.get('artists', [])) or 'Unknown',
                    'album': res.get('title', ''),
                    'thumbnail': (res.get('thumbnails') or [{}])[-1].get('url', ''),
                    'duration': r.get('duration_seconds', 0)
                })
        return json.dumps({
            "success": True,
            "title": res.get('title', ''),
            "artist": ', '.join(a['name'] for a in res.get('artists', [])) if res.get('artists') else 'Unknown',
            "thumbnail": (res.get('thumbnails') or [{}])[-1].get('url', ''),
            "tracks": tracks
        })
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

def get_lyrics(title, artist, duration_seconds=None):
    try:
        # Clean common parentheses and brackets from title
        clean_title = re.sub(r'\s*[\(\[].*?[\)\]]', '', title).strip()
        # Clean common YouTube descriptors
        clean_title = re.sub(r'(?i)\b(video song|lyrical video|lyrical|video|full song|official video|official audio|audio|music video|lyric video|lyrics video|lyrics|karaoke)\b', '', clean_title).strip()
        
        # Split title by common title-artist separators like '|', '-', ':', 'feat.'
        splitters = r'\s*\|\s*|\s*-\s*|\s*:\s*|\s*feat\.\s*'
        clean_title = re.split(splitters, clean_title, flags=re.IGNORECASE)[0].strip()
        
        # Split artist by common separators (comma, ampersand, 'and', semicolon)
        artist_separators = r',|&|\band\b|;'
        artists_list = [a.strip() for a in re.split(artist_separators, artist, flags=re.IGNORECASE) if a.strip()]
        primary_artist = artists_list[0] if artists_list else artist.strip()
        
        # Build search query candidates
        candidates = [(clean_title, primary_artist)]
        
        # Fetch from iTunes Search API as a fallback to normalize title/artist spellings
        try:
            itunes_url = f"https://itunes.apple.com/search?term={urllib.parse.quote(clean_title + ' ' + primary_artist)}&entity=song&limit=1"
            req = urllib.request.Request(itunes_url, headers={'User-Agent': 'Echonix/1.0'})
            with urllib.request.urlopen(req, timeout=5) as r:
                itunes_data = json.loads(r.read())
            if itunes_data.get('results'):
                res = itunes_data['results'][0]
                it_title = res.get('trackName', '')
                it_artist = res.get('artistName', '').split(',')[0].split('&')[0].strip()
                it_clean_title = re.sub(r'\s*[\(\[].*?[\)\]]', '', it_title).strip()
                it_clean_title = re.split(splitters, it_clean_title, flags=re.IGNORECASE)[0].strip()
                if it_clean_title and it_clean_title.lower() != clean_title.lower():
                    candidates.append((it_clean_title, it_artist))
        except:
            pass

        # Generate phonetic spelling variations for Tamil/Indian songs (ee <-> ay, oo <-> u, etc.)
        phonetic_title = clean_title
        if 'ee' in phonetic_title.lower():
            phonetic_title = re.sub(r'(?i)ee', 'ay', phonetic_title)
        elif 'ay' in phonetic_title.lower():
            phonetic_title = re.sub(r'(?i)ay', 'ee', phonetic_title)
            
        if phonetic_title.lower() != clean_title.lower():
            candidates.append((phonetic_title, primary_artist))

        # Helper to search and find best match in list of tracks based on overlap scoring
        def find_best_match(results, tgt_title, tgt_artists):
            best_track = None
            best_score = -1
            
            for track in results:
                score = 0
                track_title = track.get('name', '').lower()
                track_artist = track.get('artistName', '').lower()
                
                # Title similarity check
                if tgt_title.lower() in track_title or track_title in tgt_title.lower():
                    score += 10
                    
                # Artist matching: check if any of our input artists overlap with result artist
                for a in tgt_artists:
                    a_clean = a.lower()
                    if a_clean in track_artist or track_artist in a_clean:
                        score += 20
                        break # Only add artist bonus once
                
                # Synced lyrics bonus
                if track.get('syncedLyrics'):
                    score += 5
                elif track.get('plainLyrics'):
                    score += 2
                    
                if score > best_score:
                    best_score = score
                    best_track = track
                    
            return best_track if best_score >= 10 else None

        # Increase timeout to 10s to prevent read/connection timeout errors with LRCLIB
        TIMEOUT_SEC = 10

        # Try direct GET for all candidates
        for t_title, t_artist in candidates:
            try:
                url = f"https://lrclib.net/api/get?artist_name={urllib.parse.quote(t_artist)}&track_name={urllib.parse.quote(t_title)}"
                if duration_seconds is not None:
                    url += f"&duration={int(duration_seconds)}"
                req = urllib.request.Request(url, headers={'User-Agent': 'Echonix/1.0'})
                with urllib.request.urlopen(req, timeout=TIMEOUT_SEC) as r:
                    data = json.loads(r.read())
                if data.get('syncedLyrics'):
                    return json.dumps({"success": True, "synced": True, "lyrics": data['syncedLyrics']})
                if data.get('plainLyrics'):
                    return json.dumps({"success": True, "synced": False, "lyrics": data['plainLyrics']})
            except:
                pass

        # Try specific search for all candidates
        for t_title, t_artist in candidates:
            try:
                sq = f"{t_title} {t_artist}"
                url = f"https://lrclib.net/api/search?q={urllib.parse.quote(sq)}"
                req = urllib.request.Request(url, headers={'User-Agent': 'Echonix/1.0'})
                with urllib.request.urlopen(req, timeout=TIMEOUT_SEC) as r:
                    results = json.loads(r.read())
                best = find_best_match(results, t_title, [t_artist])
                if best:
                    if best.get('syncedLyrics'):
                        return json.dumps({"success": True, "synced": True, "lyrics": best['syncedLyrics']})
                    if best.get('plainLyrics'):
                        return json.dumps({"success": True, "synced": False, "lyrics": best['plainLyrics']})
            except:
                pass

        # Failsafe: Try broad search with track title only for all candidates
        for t_title, t_artist in candidates:
            try:
                url = f"https://lrclib.net/api/search?q={urllib.parse.quote(t_title)}"
                req = urllib.request.Request(url, headers={'User-Agent': 'Echonix/1.0'})
                with urllib.request.urlopen(req, timeout=TIMEOUT_SEC) as r:
                    results = json.loads(r.read())
                best = find_best_match(results, t_title, [t_artist])
                if best:
                    if best.get('syncedLyrics'):
                        return json.dumps({"success": True, "synced": True, "lyrics": best['syncedLyrics']})
                    if best.get('plainLyrics'):
                        return json.dumps({"success": True, "synced": False, "lyrics": best['plainLyrics']})
            except:
                pass

        return json.dumps({"success": False, "error": "No lyrics found."})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

def resolve_stream(video_id):
    global ytm_cache_path
    try:
        # Check offline file
        if ytm_cache_path:
            dl_dir = os.path.join(ytm_cache_path, "downloads")
            # 1. New naming scheme: {video_id}.m4a
            new_path = os.path.join(dl_dir, f"{video_id}.m4a")
            if os.path.exists(new_path) and os.path.getsize(new_path) > 1000:
                return json.dumps({
                    "success": True,
                    "url": new_path,
                    "ext": "m4a",
                    "headers": {},
                    "expires_at": int(time.time()) + 86400 * 365,
                    "is_local": True
                })
            # 2. Legacy check:
            if os.path.exists(dl_dir):
                for file in os.listdir(dl_dir):
                    if file.endswith(".json"):
                        meta_path = os.path.join(dl_dir, file)
                        try:
                            with open(meta_path, 'r', encoding='utf-8') as f:
                                data = json.load(f)
                            if data.get('id') == video_id:
                                mp3_path = meta_path.replace(".json", "")
                                if os.path.exists(mp3_path) and os.path.getsize(mp3_path) > 1000:
                                    ext = "m4a" if mp3_path.endswith(".m4a") else "mp3"
                                    return json.dumps({
                                        "success": True,
                                        "url": mp3_path,
                                        "ext": ext,
                                        "headers": {},
                                        "expires_at": int(time.time()) + 86400 * 365,
                                        "is_local": True
                                    })
                        except:
                            pass

        opts = {
            'format': 'bestaudio[ext=m4a]/bestaudio',
            'quiet': True,
            'no_warnings': True,
            'noplaylist': True,
            'socket_timeout': 30,
            'geo_bypass': True,
            'nocheckcertificate': True,
            'http_headers': {
                'User-Agent': 'com.google.android.apps.youtube.music/5.28.1 (Linux; U; Android 11) gzip',
            },
            'extractor_args': {
                'youtube': {'player_client': ['android_vr']}
            }
        }
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(f'https://www.youtube.com/watch?v={video_id}', download=False)
            stream_url = info.get('url')
            if not stream_url:
                formats = info.get('formats') or []
                for f in reversed(formats):
                    if f.get('vcodec') == 'none' and f.get('url'):
                        stream_url = f.get('url')
                        break
            if not stream_url:
                return json.dumps({"success": False, "error": "No stream URL found."})

            ext = info.get('ext', 'm4a')
            headers = info.get('http_headers', {})
            expires_at = int(time.time()) + 1800
            try:
                parsed_url = urllib.parse.urlparse(stream_url)
                params = urllib.parse.parse_qs(parsed_url.query)
                if 'expire' in params:
                    expires_at = int(params['expire'][0]) - 300
            except:
                pass

            return json.dumps({
                "success": True,
                "url": stream_url,
                "ext": ext,
                "headers": headers,
                "expires_at": expires_at,
                "is_local": False
            })
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

def resolve_stream_download(video_id):
    global ytm_cache_path
    try:
        tmp_dir = os.path.join(ytm_cache_path, "tmp_audio")
        os.makedirs(tmp_dir, exist_ok=True)
        out_tmpl = os.path.join(tmp_dir, f"{video_id}.%(ext)s")
        opts = {
            'format': 'bestaudio[ext=m4a]/bestaudio',
            'outtmpl': out_tmpl,
            'quiet': True,
            'no_warnings': True,
            'noplaylist': True,
            'socket_timeout': 30,
            'geo_bypass': True,
            'nocheckcertificate': True,
            'http_headers': {
                'User-Agent': 'com.google.android.apps.youtube.music/5.28.1 (Linux; U; Android 11) gzip',
            },
            'extractor_args': {
                'youtube': {'player_client': ['android_vr']}
            }
        }
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(f'https://www.youtube.com/watch?v={video_id}', download=True)
            ext = info.get('ext', 'm4a')
            final_path = os.path.join(tmp_dir, f"{video_id}.{ext}")
            if os.path.exists(final_path) and os.path.getsize(final_path) > 1000:
                return json.dumps({
                    "success": True,
                    "url": final_path,
                    "ext": ext,
                    "headers": {},
                    "expires_at": int(time.time()) + 86400 * 365,
                    "is_local": True
                })
            return json.dumps({"success": False, "error": "Download produced empty file."})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

def get_stream_url(video_id):
    return resolve_stream(video_id)


def rate_song(video_id, rating):
    global ytm
    if not ytm:
        return json.dumps({"success": False, "error": "YTMusic not initialized"})
    if rating not in ('LIKE', 'DISLIKE', 'INDIFFERENT'):
        return json.dumps({"success": False, "error": f"Invalid rating '{rating}'. Must be LIKE, DISLIKE, or INDIFFERENT."})
    try:
        ytm.rate_song(video_id, rating)
        return json.dumps({"success": True})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

def add_history(video_id):
    global ytm
    if not ytm:
        return json.dumps({"success": False, "error": "YTMusic not initialized"})
    try:
        try:
            song_info = ytm.get_song(video_id)
            ytm.add_history_item(song_info)
        except:
            pass
        return json.dumps({"success": True})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

def get_liked_songs():
    global ytm
    if not ytm:
        return json.dumps({"success": False, "error": "YTMusic not initialized"})
    try:
        res = ytm.get_liked_songs(limit=100)
        tracks = []
        for r in res.get('tracks', []):
            vid = r.get('videoId')
            if vid:
                tracks.append({
                    'id': vid,
                    'title': r.get('title', ''),
                    'artist': ', '.join(a['name'] for a in r.get('artists', [])) or 'Unknown',
                    'album': r.get('album', {}).get('name', '') if r.get('album') else '',
                    'thumbnail': (r.get('thumbnails') or [{}])[-1].get('url', ''),
                    'duration': r.get('duration_seconds', 0)
                })
        return json.dumps({"success": True, "songs": tracks})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

def download_song(video_id, title, artist, thumbnail_url="", playlist_name=""):
    import threading
    t = threading.Thread(target=_download_song_thread, args=(video_id, title, artist, thumbnail_url, playlist_name))
    t.start()
    return json.dumps({"success": True, "message": "Download started in background"})

def _download_song_thread(video_id, title, artist, thumbnail_url="", playlist_name=""):
    global ytm_cache_path
    try:
        import os
        safe_title = "".join(c for c in title if c.isalnum() or c in (' ', '_', '-')).rstrip()
        safe_artist = "".join(c for c in artist if c.isalnum() or c in (' ', '_', '-')).rstrip()
        filename = f"{safe_artist} - {safe_title}.mp3"

        dl_dir = os.path.join(ytm_cache_path, "downloads")
        os.makedirs(dl_dir, exist_ok=True)
        out_path = os.path.join(dl_dir, filename)

        opts = {
            'format': '251/140/bestaudio/best',
            'outtmpl': out_path,
            'quiet': True,
            'no_warnings': True,
            'noplaylist': True,
            'nocheckcertificate': True,
            'http_headers': {
                'User-Agent': 'com.google.android.apps.youtube.music/5.28.1 (Linux; U; Android 11) gzip',
            },
            'extractor_args': {
                'youtube': {'player_client': ['android_music', 'ios', 'android', 'web']}
            }
        }
        with yt_dlp.YoutubeDL(opts) as ydl:
            ydl.download([f'https://www.youtube.com/watch?v={video_id}'])

        # Try to download lyrics
        lyrics_data = None
        try:
            l_res = json.loads(get_lyrics(title, artist))
            if l_res.get("success") == True:
                lyrics_data = {
                    "synced": l_res.get("synced", False),
                    "lyrics": l_res.get("lyrics", "")
                }
        except Exception as lex:
            print(f"Lyrics download error: {lex}")

        meta_path = out_path + ".json"
        with open(meta_path, 'w') as f:
            json.dump({
                "id": video_id,
                "title": title,
                "artist": artist,
                "path": out_path,
                "thumbnail_url": thumbnail_url,
                "playlist_name": playlist_name,
                "lyrics_data": lyrics_data
            }, f)
    except Exception as e:
        print(f"Download error: {e}")

def redownload_lyrics(video_id, title, artist):
    global ytm_cache_path
    try:
        import os
        safe_title = "".join(c for c in title if c.isalnum() or c in (' ', '_', '-')).rstrip()
        safe_artist = "".join(c for c in artist if c.isalnum() or c in (' ', '_', '-')).rstrip()
        filename = f"{safe_artist} - {safe_title}.mp3"
        dl_dir = os.path.join(ytm_cache_path, "downloads")
        meta_path = os.path.join(dl_dir, filename + ".json")
        
        if not os.path.exists(meta_path):
            return json.dumps({"success": False, "error": "Song metadata not found"})

        l_res = json.loads(get_lyrics(title, artist))
        if l_res.get("success") == True:
            lyrics_data = {
                "synced": l_res.get("synced", False),
                "lyrics": l_res.get("lyrics", "")
            }
            # Read existing metadata
            with open(meta_path, 'r') as f:
                data = json.load(f)
            data["lyrics_data"] = lyrics_data
            # Save metadata
            with open(meta_path, 'w') as f:
                json.dump(data, f)
            return json.dumps({"success": True, "lyrics_data": lyrics_data})
        else:
            return json.dumps({"success": False, "error": "Lyrics not found online"})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

def get_search_suggestions(query):
    global ytm
    if not ytm:
        return json.dumps({"success": False, "error": "YTMusic not initialized"})
    try:
        queries = ytm.get_search_suggestions(query)
        return json.dumps({
            "success": True,
            "queries": queries,
        })
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

def get_trending_searches(country='ZZ'):
    global ytm
    if not ytm:
        return json.dumps({"success": False, "error": "YTMusic not initialized"})
    try:
        try:
            charts = ytm.get_charts(country=country if country else 'ZZ')
        except Exception:
            charts = ytm.get_charts(country='ZZ')
        songs = []
        for s in charts.get('songs', {}).get('items', [])[:6]:
            songs.append({
                'title': s.get('title', ''),
                'artist': ', '.join(a['name'] for a in s.get('artists', [])) if s.get('artists') else '',
                'thumbnail': (s.get('thumbnails') or [{}])[-1].get('url', ''),
                'id': s.get('videoId', ''),
                'type': 'song'
            })
        albums = []
        for a in charts.get('albums', {}).get('items', [])[:6]:
            albums.append({
                'title': a.get('title', ''),
                'artist': ', '.join(art['name'] for art in a.get('artists', [])) if a.get('artists') else '',
                'thumbnail': (a.get('thumbnails') or [{}])[-1].get('url', ''),
                'id': a.get('browseId', ''),
                'type': 'album'
            })
        return json.dumps({
            "success": True,
            "songs": songs,
            "albums": albums
        })
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

def get_downloaded_songs():
    global ytm_cache_path
    try:
        import os
        dl_dir = os.path.join(ytm_cache_path, "downloads")
        if not os.path.exists(dl_dir):
            return json.dumps({"success": True, "songs": []})

        songs = []
        for file in os.listdir(dl_dir):
            if file.endswith(".json"):
                meta_path = os.path.join(dl_dir, file)
                try:
                    with open(meta_path, 'r') as f:
                        data = json.load(f)
                        songs.append(data)
                except:
                    pass
        return json.dumps({"success": True, "songs": songs})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

WHITELIST = {
    'init_ytmusic': init_ytmusic,
    'login_with_cookie': login_with_cookie,
    'logout': logout,
    'check_auth_status': check_auth_status,
    'get_home_feed': get_home_feed,
    'search_songs': search_songs,
    'get_playlist_details': get_playlist_details,
    'get_album_details': get_album_details,
    'get_lyrics': get_lyrics,
    'get_stream_url': get_stream_url,
    'resolve_stream': resolve_stream,
    'resolve_stream_download': resolve_stream_download,
    'rate_song': rate_song,
    'add_history': add_history,
    'get_liked_songs': get_liked_songs,
    'download_song': download_song,
    'redownload_lyrics': redownload_lyrics,
    'get_search_suggestions': get_search_suggestions,
    'get_trending_searches': get_trending_searches,
    'get_downloaded_songs': get_downloaded_songs,
}

def dispatch(fn_name: str, args_json: str) -> str:
    if fn_name not in WHITELIST:
        return json.dumps({"success": False, "error": "unknown function"})
    try:
        kwargs = json.loads(args_json) if args_json else {}
        fn = WHITELIST[fn_name]
        res = fn(**kwargs)
        if res is None:
            return json.dumps({"success": True})
        if isinstance(res, str):
            return res
        return json.dumps(res)
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})

