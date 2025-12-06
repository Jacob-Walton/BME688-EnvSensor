# BME688 Environment Monitor

Environment monitor powered by the BOSCH SensorTec BME688 over I2C.

## Prerequisites

### BSEC Library

Please obtain a copy of `libalgobsec.a` from this page:  
[www.bosch-sensortec.com/software-tools/software/bme688-and-bme690-software](https://www.bosch-sensortec.com/software-tools/software/bme688-and-bme690-software/#:~:text=BME688%20Development%20Kit%20Software). Please go to the form titled **BME688 Development Kit Software**.

Fill out the form and use the download link sent to your email.

After downloading, you will receive a file named something like: `bsec_vx-x-x-x.zip`. Extract the archive and locate:

```bash
algo/bsec_IAQ/bin/RaspberryPi/PiFour_Armv8/libalgobsec.a
```

Copy this `libalgobsec.a` file into the `lib/` directory of this project.

This version is suitable for the Raspberry Pi 4 and also works on the Raspberry Pi 5.

### METAR API

This project can optionally use the **AVWX** open-source METAR API to retrieve aviation weather data.

You have three choices:

1. Use the hosted AVXW service.
2. Self-host the AVXW API using their open-source REST API.
3. Disable METAR lookups entirely by leaving the relevant .env values blank.

Configure the following in your `.env` file:

- `API_URL`: endpoint for the AVWX API
- `API_KEY`: API key for hosted or self-hosted instances

[AVWX API GitHub](https://github.com/avwx-rest/avwx-api)
