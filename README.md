This script is for DCS (digital combat simulator) mission creators. 
It allows to set up an air race track with little effort.

The script will be part of the mission file (.miz) you create and track 
timing and violations of the participating airplanes.

All you need to do is:
1. Set up the gates: place single or pairs of pylons along the race track. 
   You may use any object. Static objects work best for performance.
   The track may or may not end where it starts.
2. Surround each pylon with a trigger zone and name them "pilone #001", "pilone #002", ...
3. Add a trigger zone to each gate and name them "gate #001", "gate #002", ...
   If the same gate is used multiple times during the track, create multiple gate trigger
   zones on top of each other.
4. Create one or more trigger zones covering the entire race track, allowing to detect if 
   participants entered or left the race track. 
   Name them "racetrack #001", "racetrack #002", ...
5. Create three script triggers to initialize and run this script. See the comment
   block at the start of the script.
6. Add a dummy trigger that plays all sound files. This makes sure, they are added to the
   mission file.
