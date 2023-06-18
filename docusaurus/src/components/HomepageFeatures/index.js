import React from 'react';
import clsx from 'clsx';
import styles from './styles.module.css';

const FeatureList = [
  {
    title: 'AI at Your Fingertips',
    path: '/img/terminal.png',
    description: (
      <>
        PowerShellAI is designed to bring the power of the bleeding edge AI tools to the terminal.
      </>
    ),
  },
  {
    title: 'Integrated with the Latest Tools',
    path: '/img/openai.png',
    description: (
      <>
        PowerShellAI integrates with the latest APIs provided by OpenAI and can connect to private Azure OpenAI instances.
      </>
    ),
  },
  {
    title: 'Open Source',
    path: '/img/opensource.png',
    description: (
      <>
        The project is fully open source and welcoming of community contributions.
      </>
    ),
  },
];

function Feature({path, title, description}) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        <img src={path} className={styles.featureSvg} role="img" />
      </div>
      <div className="text--center padding-horiz--md">
        <h3>{title}</h3>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
