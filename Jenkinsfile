// Palette Edge — build + deploy pipeline
// Declarative pipeline; all logic lives in versioned ci/*.sh scripts.
// See BUILD-PIPELINE.md for one-time setup (privileged namespace, credentials, services).

pipeline {
  // Build runs on a tools+dind pod (build-agent-pod.yaml). The Deploy stage overrides to
  // a qemu pod with /dev/kvm (qemu-agent-pod.yaml). ISO crosses via the edge-iso server;
  // build/outputs.env crosses via stash.
  agent {
    kubernetes {
      yamlFile 'ci/build-agent-pod.yaml'
      defaultContainer 'tools'
    }
  }

  parameters {
    text(name: 'CONFIG_BUNDLE',   defaultValue: '', description: 'Paste the generator edge-build.json contents ("Copy bundle" button). Preferred over the fields below.')
    text(name: 'ARG_CONTENT',     defaultValue: '', description: 'Fallback: paste the generated .arg contents')
    text(name: 'USERDATA_CONTENT',defaultValue: '', description: 'Fallback: paste the generated user-data contents (use ${REGISTRATION_TOKEN}/${OS_PASSWORD} placeholders)')
    text(name: 'BYOOS_CONTENT',   defaultValue: '', description: 'Optional: paste the byoos profile contents')
    string(name: 'CANVOS_VERSION',defaultValue: 'v4.9.10', description: 'CanvOS tag to build with')
    booleanParam(name: 'DEPLOY',  defaultValue: false, description: 'After build, boot the ISO as a QEMU VM and verify it registers in Palette')
  }

  environment {
    // Secrets — bound from the Jenkins credential store, never hard-coded.
    PALETTE_API_KEY     = credentials('palette-api-key')
    REGISTRATION_TOKEN  = credentials('edge-registration-token')
    OS_PASSWORD         = credentials('os-password')
    // Palette tenant: cust-eng / SA-Dan-Speers project.
    PALETTE_API         = 'https://cust-eng.console.spectrocloud.com'
    PALETTE_PROJECT_UID = '6539402abeefa11ca7267d44'
    WORKDIR             = "${WORKSPACE}/build"
  }

  stages {
    stage('Setup') {
      steps { sh 'apk add --no-cache bash jq curl gettext git' }
    }

    stage('Preflight') {
      steps { sh './ci/lib.sh preflight' }
    }

    stage('Render config') {
      steps { sh './ci/render-config.sh' }   // bundle OR paste params -> build/{arg,user-data,byoos.yaml}; substitutes secret placeholders
    }

    stage('Build artifacts') {
      // 'tools' (docker CLI -> dind): builds CanvOS, docker-pushes the provider image to
      // registry.cabin, publishes the ISO to edge-iso.cabin. Writes build/outputs.env.
      steps {
        sh './ci/build-canvos.sh'
        stash name: 'edge-outputs', includes: 'build/outputs.env'
      }
    }

    stage('Deploy & verify') {
      when { expression { return params.DEPLOY } }
      // Own pod: qemu + /dev/kvm, pinned to a KVM node. Boots the ISO, polls Palette,
      // tears down — all in one stage so the VM persists across launch -> verify.
      agent {
        kubernetes {
          yamlFile 'ci/qemu-agent-pod.yaml'
          defaultContainer 'qemu'
        }
      }
      steps {
        unstash 'edge-outputs'
        sh 'apk add --no-cache bash qemu-system-x86_64 qemu-img curl jq'
        sh './ci/qemu-launch-edge.sh'
        sh './ci/wait-palette-register.sh'
      }
      post {
        failure { sh './ci/lib.sh dump_vm_console || true' }
        always  { sh './ci/qemu-teardown.sh || true' }
      }
    }
  }

  post {
    success { echo 'Edge artifacts built' + (params.DEPLOY ? ' and edge host registered.' : '.') }
    always  { archiveArtifacts artifacts: 'build/outputs.env', allowEmptyArchive: true }
  }
}
