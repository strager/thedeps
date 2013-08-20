#include <dirent.h>
#include <stdio.h>
#include <sys/stat.h>

int
main(int argc, char **argv) {
    const char *dir_path = argc > 1 ? argv[1] : ".";

    DIR *dir = opendir(dir_path);
    if (!dir) {
        perror("opendir");
        return 1;
    }

    struct dirent *entry;
    while ((entry = readdir(dir))) {
		  FILE *file = fopen(entry->d_name, "r");
		  if (!file) {
				printf("%s\n", entry->d_name);
				continue;
		  }

		  char signature[4] = { 0 };
		  fread(signature, 1, sizeof(char), file);

		  /* Use fstat to try and confuse thedeps. */
		  struct stat stat;
		  int err = fstat(fileno(file), &stat);
		  if (err) {
				printf("%s\n", entry->d_name);
				continue;
		  }

		  printf("%s %llu {%02X %02X %02X %02X}\n",
				entry->d_name,
				stat.st_size,
				signature[0],
				signature[1],
				signature[2],
				signature[3]);
    }

    closedir(dir);
    return 0;
}
