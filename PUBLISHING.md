# GitHub publishing checklist

This repository is prepared locally on the `main` branch. No remote and no GitHub upload has been created.

Before adding a remote or pushing:

1. Run `git status` and confirm that only the application source, documentation, and `.gitignore` are included.
2. Do **not** include a real CATEnv profile, CATSettings directory, `licenses.CATSettings`, CAD document, log, generated plan JSON, or desktop shortcut.
3. Replace placeholder/support text with your organization's support contact if needed.
4. Review the licensing and trademark position before using Dassault/CATIA names or artwork in a public repository. The app uses the locally installed CATIA executable's icon only for the locally generated shortcut; it does not ship an extracted CATIA icon.
5. Sign the PowerShell script or distribute a signed installer for public releases. The launcher deliberately uses `RemoteSigned`, not `Bypass`.

To publish, create an empty GitHub repository, add it as `origin`, then commit and push from a trusted local terminal with your own Git identity. Uploading is intentionally not automated by this tool.
