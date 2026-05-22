FROM furtive-tools

# Default "furtive" matches the user baked into Containerfile.tools so canonical
# container builds (make container-app with no --build-arg) are unaffected.
# The dev container passes USERNAME=${localEnv:USER} so SSH / gitconfig mounts
# at /home/$USER/... inside the container resolve correctly.
ARG USERNAME="furtive"

USER root
RUN if [ "$USERNAME" != "furtive" ]; then \
      usermod -l "$USERNAME" -d "/home/$USERNAME" -m furtive && \
      groupmod -n "$USERNAME" furtive && \
      ln -sf "/home/$USERNAME" /home/furtive && \
      echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"; \
    fi
ENV USER=$USERNAME
USER $USERNAME

ARG GRADLE_HEAP=4g

COPY --chown=$USERNAME:$USERNAME . /app/
WORKDIR /app

# Install Flutter version specified in .fvmrc (no-op if it matches tools stage)
RUN fvm install

# Reuse makefile targets so container build matches local setup
RUN make deps
RUN make build-runner

# Configure Gradle for containerized builds
RUN mkdir -p $HOME/.gradle \
 && echo "org.gradle.daemon=false" > $HOME/.gradle/gradle.properties \
 && echo "org.gradle.jvmargs=-Xmx${GRADLE_HEAP} -XX:+HeapDumpOnOutOfMemoryError" >> $HOME/.gradle/gradle.properties
