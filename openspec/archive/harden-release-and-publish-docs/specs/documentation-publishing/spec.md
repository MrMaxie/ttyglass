## ADDED Requirements

### Requirement: The documentation site is publicly deployed

The project MUST publish the generated Astro documentation from the accepted `master` branch through GitHub Pages at `https://maxie.dev/ttyglass/`. Pull requests that change the documentation source, generated site, or deployment workflow MUST build and validate the site without deploying it.

#### Scenario: Documentation reaches the accepted branch

- **WHEN** a documentation-related change is pushed to `master`
- **THEN** the workflow validates and builds the static site
- **AND** deploys the generated `docs/` directory through the GitHub Pages environment
- **AND** verifies that the public site responds successfully

#### Scenario: Documentation is proposed in a pull request

- **WHEN** a pull request changes documentation source, generated output, package metadata, or the Pages workflow
- **THEN** the workflow validates and builds the site
- **AND** does not deploy the pull request content

### Requirement: Public project metadata links to the documentation

The npm package metadata, README, and GitHub repository homepage MUST identify `https://maxie.dev/ttyglass/` as the public documentation site.

#### Scenario: A user discovers ttyglass from npm or GitHub

- **WHEN** a user inspects the package metadata, README, or repository summary
- **THEN** the public documentation URL is available without requiring knowledge of the Pages deployment structure
