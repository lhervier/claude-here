# claude-ici

Lance Claude Code sous un compte Windows dédié, isolé de ton compte, dans le dossier de ton choix :
par clic droit dans l'Explorateur (« Ouvrir Claude ici ») ou avec la commande `claude-ici`.

## Prérequis

- Un compte local dédié à Claude, non administrateur, auquel on s'est connecté au moins une fois.
- Dans ce compte : Windows Terminal et Claude Code.

## Installation

Double-clic sur `installer.cmd`, depuis **ton** compte (pas besoin d'être administrateur).
L'installeur liste les comptes locaux et te demande celui sous lequel lancer Claude, puis :

- copie le lanceur (`claude-ici.ps1` renseigné et `claude-ici.cmd`) dans
  `%LOCALAPPDATA%\Programs\ClaudeIci`, et ajoute ce dossier à ton PATH ;
- copie `claude-session.ps1` dans `C:\ProgramData\ClaudeIci`, lisible par le compte Claude mais
  pas modifiable par lui ;
- crée l'entrée du menu contextuel. Sous Windows 11, elle est dans « Afficher plus d'options »
  (ou Maj+clic droit).

Relancer l'installeur met l'installation à jour.

## Utilisation

- Clic droit sur un dossier, dans le vide d'un dossier ou sur un lecteur : « Ouvrir Claude ici ».
- Dans une console : `claude-ici [dossier]` (dossier courant par défaut).

Le mot de passe du compte Claude est demandé à chaque lancement (`runas`). Le dossier doit être
accessible à ce compte : pas dans ton profil.

Windows Terminal et Claude Code doivent être installés dans le compte Claude : `claude-ici` les
cherche dans le PATH de ce compte, puis dans `%USERPROFILE%\Tools\WindowsTerminal` et
`%USERPROFILE%\.local\bin`, et indique celui qui manque.

## Désinstallation

```powershell
.\installer.cmd -Desinstaller
```
## Fichiers

| Fichier              | Rôle                                                                     |
| -------------------- | ------------------------------------------------------------------------ |
| `installer.cmd`      | Lance `installer.ps1` (double-clic).                                     |
| `installer.ps1`      | Installe, met à jour ou désinstalle.                                     |
| `claude-ici.ps1`     | Modèle du lanceur (ton compte) : l'installeur y écrit le compte Claude.  |
| `claude-session.ps1` | Tourne sous le compte Claude : vérifie les prérequis, puis lance Claude.  |
