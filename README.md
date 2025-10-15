# Voice Note to Journal Automation
This project provides a robust, event-driven automation workflow for a Linux environment (specifically Manjaro) to turn voice notes into version-controlled journal entries.

It watches a directory for new audio files (synced from a phone via Syncthing), transcribes them, processes the text with a custom AI prompt (via [Fabric](https://github.com/danielmiessler/Fabric/)), appends the result to a journal file, and commits the change to a Git repository (like [Telos](https://github.com/danielmiessler/Telos/)).

## Features
- Event-Driven: Uses systemd.path to instantly trigger on new files, consuming minimal resources.
- Reliable & Resilient: Each voice note is archived before processing. The original file is only deleted upon the successful completion of the entire workflow, allowing for easy recovery.
- High-Quality Transcription: Integrates faster-whisper, a high-performance implementation of OpenAI's Whisper model that runs efficiently on CPU.
- Configurable: All paths, models, and patterns are managed in a central configuration file.
- Automated Git Commits: Keeps your journal synchronized and version-controlled automatically.
- Detailed Logging: Logs every step, making monitoring and troubleshooting straightforward.

## How It Works
1. You record a voice note on your phone.
2. Syncthing automatically syncs the audio file to the ~/voicenotes/in directory on your Linux machine.
3. A systemd.path unit, which is watching this directory, detects the new file.
4. The path unit triggers the voicenote-processor.service.
5. This service executes the process-voicenote.sh script, passing the path of the new file to it.
6. The script performs the following actions:
   1. Archive: A timestamped copy of the audio file is saved to the archive directory.
   2. Transcribe: faster-whisper converts the audio to raw text.
   3. Process: The raw text is piped to a fabric pattern to be summarized or formatted.
   4. Update: The formatted output is appended to your journal file.
   5. Commit: The script stages, commits, and pushes the changes to your Git repository.
   6. Cleanup: If all previous steps succeeded, the original audio file in the in directory is deleted. Syncthing syncs this deletion back to your phone.

## Prerequisites
- A Manjaro Linux system (or other Arch-based distro).
- Syncthing configured to sync voice notes from your phone to a folder on the Linux machine.
- Fabric installed and configured. See the Fabric GitHub repository for instructions.
- A local clone of your Telos/journal Git repository with SSH keys configured for passwordless `git push`.

## Installation
1. Clone the Repository
```bash
git clone https://github.com/your-username/voicenote-automation.git
cd voicenote-automation
```

2. Run the Installer

The installer will handle dependencies, create directories, and set up the systemd services.
```bash
chmod +x install.sh
./install.sh
```

3. Configure the Automation
After the installer finishes, you must edit the configuration file to match your setup.

```bash
vim ~/.config/voicenote-automation/config
```

Pay close attention to `TELOS_REPO_DIR` and `TELOS_JOURNAL_FILE`.

Your automation is now live and watching for new files.

## Usage & Monitoring
### Automatic Execution
The automation runs entirely in the background. As long as the `systemd` path unit is active, any file added to your configured `VOICENOTES_IN_DIR` will be processed.

### Manual Execution
You can manually trigger processing for any audio file. This is useful for reprocessing an archived file or a file that failed previously.

```bash
# Get the script path from the service file if you're unsure
# systemctl --user cat voicenote-processor.service

/path/to/repo/bin/process-voicenote.sh /path/to/your/audio-file.m4a
```

### Monitoring the Service
Check the status of the file watcher:

```bash
systemctl --user status voicenote-processor.path
```

View the logs for the service:

```bash
journalctl --user -u voicenote-processor.service -f
```

View the detailed application logs:
The script logs its entire output to a file defined in your config (`LOG_DIR`).

```bash
tail -f ~/voicenotes/logs/automation.log
```

### Troubleshooting
#### Automation Doesn't Trigger:

1. Check that the `voicenote-processor.path` service is active (waiting).
2. Verify the path in `~/.config/systemd/user/voicenote-processor.path` matches your `VOICENOTES_IN_DIR` from the config file. Note: The systemd unit doesn't read the config file, so this path is static. If you change `VOICENOTES_IN_DIR`, you must update the `.path` file and run `systemctl --user daemon-reload.`

#### Script Fails to Run:

1. Check the service logs for errors.
2. The most common failure is a `git push` command failing due to authentication. Ensure your SSH keys are set up correctly for your Git remote.
3. Another common issue is the `fabric` pattern not being found. Verify the `FABRIC_PATTERN` name in your config.

#### Recovering a Failed Job:
If the script fails, the original file will be left in the `VOICENOTES_IN_DIR`.

1. Read the logs to understand the cause of the failure.
2. Fix the underlying issue (e.g., correct a path, fix Git auth).
3. Manually re-trigger the job by "touching" the file: `touch ~/voicenotes/in/the-failed-file.m4a`. This updates its modification time and the `systemd` watcher will trigger the service again.