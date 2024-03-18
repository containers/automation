
# Podman CI Workflow

#### Last Updated: 2024-01-23

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Quisque tincidunt dolor eu ornare vulputate. Cras tristique leo sed dignissim convallis. Donec id risus sagittis, sodales nisi a, euismod ex. Pellentesque posuere metus dui, ac finibus magna vehicula a. Pellentesque et eleifend nibh. Interdum et malesuada fames ac ante ipsum primis in faucibus. Aliquam semper purus dui, nec ornare purus lobortis eget.

```mermaid
%%{init: { "sequence": { "mirrorActors": false }}}%%

sequenceDiagram
 title Podman CI
 actor Developer
 participant github as SCM
 participant automation as Automation Service<br />cirrus & github actions
 participant bucket as Storage<br/>S3 / Google Cloud
 participant buildah as Container Service
 participant registry as Quay.io

 Note over github: Do we need to call out github<br/> vs distgit on diagrams?
 Developer->>github: Publish source
 github->>+automation: Trigger build
 automation->>automation: Build binaries
 alt When build succeeds
  automation->>automation: Execute cirrus actions/tests<br/>(subscription)
  automation->>automation: Execute github actions/tests<br/>(free-tier, throttled)

  opt When automation passes
   automation->>buildah: Trigger image build

   buildah->>buildah: Build image
   buildah->>registry: Publish image
   buildah->>bucket: Log artifacts
   buildah->>automation: Return status
   end
 else Automation fails
  automation->>Developer: Email to podman-maintainers
 end
 automation->>github: Log status
 automation->>-bucket: Log artifacts
```

Aliquam fermentum dictum efficitur. Aliquam sodales lectus eu volutpat lacinia. Sed non ullamcorper neque. Ut vitae neque at ex laoreet rhoncus non efficitur mi. Integer laoreet dignissim lorem, quis tristique ante interdum in. Morbi malesuada malesuada quam at tempus. Etiam tempor aliquet interdum.
