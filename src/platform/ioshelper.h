// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef FK_IOSHELPER_H
#define FK_IOSHELPER_H

#ifdef __cplusplus
extern "C" {
#endif

// Configure the shared audio session for game playback and keep the screen
// awake while the app is in the foreground. Safe to call before the event loop.
void fkIosPrepare(void);

// Exclude the writable game data directory from iCloud backups. The directory
// contains a cache-like copy of the bundled runtime.
void fkIosExcludeFromBackup(const char *path);

#ifdef __cplusplus
}
#endif

#endif
