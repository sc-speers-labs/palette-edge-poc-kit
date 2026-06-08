// Palette Edge — build + deploy pipeline
// Declarative pipeline; all logic lives in versioned ci/*.sh scripts.
// See BUILD-PIPELINE.md for one-time setup (privileged namespace, credentials, LXD trust).

pipeline {
  // Orchestration runs on a lightweight default agent; the Build stage overrides
  // to a privileged Earthly pod (see that stage's agent block).
  agent any

  parameters {
    // --- Config ingestion (provide ONE of these) ---
    file(name: 'CONFIG_BUNDLE',   description: 'edge-build.json from the generator "Download build bundle" button (preferred)')
    text(name: 'ARG_CONTENT',     defaultValue: '', description: 'Fallback: paste the generated .arg contents')
    text(name: 'USERDATA_CONTENT',defaultValue: '', description: 'Fallback: paste the generated user-data contents (use ${REGISTRATION_TOKEN}/${OS_PASSWORD} placeholders)')
    text(name: 'BYOOS_CONTENT',   defaultValue: '', description: 'Optional: paste the byoos profile contents')

    // --- Build knobs ---
    string(name: 'BUILD_NAME',    defaultValue: 'poc', description: 'Custom tag / VM label')
    string(name: 'CANVOS_VERSION',defaultValue: 'v4.9.10', description: 'CanvOS tag to build with')

    // --- Flow control ---
    booleanParam(name: 'DEPLOY',            defaultValue: true,  description: 'Launch an LXD edge VM after build')
    booleanParam(name: 'FORCE_REPROVISION', defaultValue: false, description: 'Rebuild the LXD host even if healthy')
    booleanParam(name: 'TEARDOWN_VM',       defaultValue: false, description: 'Delete the edge VM after verification (ephemeral test loop)')
  }

  environment {
    // Secrets — bound from the Jenkins credential store, never hard-coded.
    MAAS_OAUTH          = credentials('maas-oauth')
    PALETTE_API_KEY     = credentials('palette-api-key')
    REGISTRATION_TOKEN  = credentials('edge-registration-token')
    OS_PASSWORD         = credentials('os-password')
    TTLSH_NAMESPACE     = credentials('ttlsh-namespace')
    // LXD client cert/key (secret files) — already trusted on the LXD host.
    LXD_CLIENT_CRT      = credentials('lxd-client-crt')
    LXD_CLIENT_KEY      = credentials('lxd-client-key')
    // The LXD host is selected by ROLE, not identity: any Deployed machine tagged
    // LXD_HOST_TAG. Its endpoint is discovered from MaaS each run (no DNS alias).
    LXD_HOST_TAG        = 'lxd-host'
    // LXD_HOST_POOL    = '<pool>'  // optional: restrict new candidates to a MaaS pool
    // LXD_HOST_SYSTEM_ID = '<id>'  // optional override: pin to one specific machine
    MAAS_API            = 'http://homelab.cabin:5240/MAAS/api/2.0'
    WORKDIR             = "${WORKSPACE}/build"
  }

  options { timestamps(); ansiColor('xterm') }

  stages {
    stage('Preflight') {
      steps { sh './ci/lib.sh preflight' }
    }

    stage('Render config') {
      steps { sh './ci/render-config.sh' }   // bundle OR paste params -> build/{arg,user-data,byoos.yaml}; substitutes secret placeholders
    }

    stage('Build artifacts') {
      agent {
        kubernetes {
          // Privileged Earthly/buildkit pod in the dedicated privileged-PSA namespace.
          yamlFile 'ci/build-agent-pod.yaml'
          defaultContainer 'earthly'
        }
      }
      steps { sh './ci/build-canvos.sh' }     // -> pushes provider image to ttl.sh, publishes ISO, writes build/outputs.env
    }

    stage('Ensure LXD host') {
      when { expression { return params.DEPLOY } }
      steps { sh './ci/maas-ensure-lxd-host.sh' }   // idempotent reconcile: deploy/power-on/repair via MaaS, re-init LXD if needed
    }

    stage('Deploy edge VM') {
      when { expression { return params.DEPLOY } }
      steps { sh './ci/lxd-launch-edge.sh' }        // lxc init --empty --vm + attach ISO + boot -> writes build/vm.env
    }

    stage('Verify registration') {
      when { expression { return params.DEPLOY } }
      steps { sh './ci/wait-palette-register.sh' }  // poll Palette API until the edge host registers
    }

    stage('Teardown VM') {
      when { expression { return params.DEPLOY && params.TEARDOWN_VM } }
      steps { sh './ci/lxd-teardown.sh' }
    }
  }

  post {
    success { echo 'Edge host built' + (params.DEPLOY ? ' and registered.' : '.') }
    failure { sh 'test -f build/vm.env && ./ci/lib.sh dump_vm_console || true' }
    always  { archiveArtifacts artifacts: 'build/outputs.env', allowEmptyArchive: true }
  }
}
